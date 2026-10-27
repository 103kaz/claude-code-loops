#!/usr/bin/env bash
# PreToolUse hook (Bash): the first `git push` for a given HEAD is blocked with
# a request to run /code-loops:review-loop. The attempt is recorded, so a retry
# of the same push (same HEAD, same push words) goes through. A new commit, or a
# different push of the same commit, asks again. Every push on the command line
# is judged, not only the first.
# It fails open: anything it cannot judge (unknown directory, no way to record
# the attempt) lets the command run.

set -f # no globbing when the command's words are split below

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  command_line=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
else
  # Without jq: pick the string values out of the JSON by hand.
  json_string() {
    printf '%s' "$input" |
      sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 |
      sed -e 's/\\n/ ; /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
  }
  command_line=$(json_string command)
  cwd=$(json_string cwd)
fi
[ -n "$cwd" ] || cwd=$PWD

# Most Bash calls have no push in them: leave before any work.
case $command_line in *push*) ;; *) exit 0 ;; esac

# A backslash-newline continuation is one line.
command_line=${command_line//$'\\\n'/ }

# Split the command line at ; & | and newlines that are outside quotes, one
# segment per line, so each `git push` is judged with its own words and directory.
segments=$(printf '%s' "$command_line" | awk '
  BEGIN { RS = "\001"; q = "" }
  {
    s = $0; n = length(s); out = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && q != "\047") { out = out c substr(s, i + 1, 1); i++; continue }
      if (q != "") { if (c == q) q = ""; out = out c; continue }
      if (c == "\047" || c == "\"") { q = c; out = out c; continue }
      if (c == ";" || c == "&" || c == "|") { out = out "\n"; continue }
      out = out c
    }
    printf "%s", out
  }')

push_re='(^|[^[:alnum:]_-])git(([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)|([[:space:]]+--?[^[:space:]]+))*[[:space:]]+push([^[:alnum:]_-]|$)'

# A leading ~ is the home directory.
expand_home() {
  case $1 in
    "~") printf '%s' "$HOME" ;;
    \~/*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# resolve <base> <dir>: <dir> as an absolute path, relative to <base> when it is not.
resolve() {
  local d
  d=$(expand_home "$2")
  case $d in
    /*) printf '%s' "$d" ;;
    *) printf '%s' "$1/$d" ;;
  esac
}

# judge <directory> <push words>: block once per (repository, HEAD, push words).
judge() {
  local dir=$1 words=$2 head top state_dir key marker
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || return 0
  top=$(git -C "$dir" rev-parse --show-toplevel)

  # Nothing new to push (upstream already has HEAD).
  if git -C "$dir" rev-parse --verify -q '@{u}' >/dev/null 2>&1 &&
    [ "$(git -C "$dir" rev-list --count '@{u}..HEAD')" = 0 ]; then
    return 0
  fi

  state_dir=${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/code-loops}
  key=$(printf '%s %s %s' "$top" "$head" "$words" | { shasum || sha1sum || cksum; } 2>/dev/null | cut -d' ' -f1)
  [ -n "$key" ] || return 0
  marker=$state_dir/$key
  [ -e "$marker" ] && return 0

  if ! { mkdir -p "$state_dir" && : >"$marker"; } 2>/dev/null; then
    echo "code-loops: cannot write $state_dir, so the pre-push review request is skipped." >&2
    return 0
  fi
  find "$state_dir" -type f -mtime +30 -delete 2>/dev/null
  return 1
}

# `cd <dir>` in an earlier segment moves the directory of the later ones. A cd
# that cannot be followed (an option, a variable, a directory that does not
# exist) leaves the directory as it was; a cd inside ( ) ends with the ).
current=$cwd
saved='' close_prev=0 blocked=0
while IFS= read -r segment; do
  if [ "$close_prev" = 1 ] && [ -n "$saved" ]; then current=$saved saved=''; fi

  # Quoted strings become "Q", so `git commit -m "git push"` does not match and
  # `git -C "my dir" push` does.
  masked=$(printf '%s' "$segment" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g")
  case $masked in *")"*) close_prev=1 ;; *) close_prev=0 ;; esac

  cd_dir=$(printf '%s' "$segment" | sed -nE "s/^[[:space:]]*[({]?[[:space:]]*cd[[:space:]]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+)).*/\2\3\4/p" | head -1)
  case $cd_dir in
    '' | -* | *'$'* | *'`'*) ;;
    *)
      target=$(resolve "$current" "$cd_dir")
      if [ -d "$target" ]; then
        case $segment in *"("*) [ -n "$saved" ] || saved=$current ;; esac
        current=$target
      fi
      ;;
  esac

  printf '%s' "$masked" | grep -Eq "$push_re" || continue

  # Pushes that do not publish commits. Only the words of the push itself count.
  push_args=$(printf '%s' "$masked" | grep -oE "${push_re}.*" | head -1 | sed -E "s/^${push_re}//")
  tags_only=0 positional=0 exempt=0
  for word in $push_args; do
    case $word in
      --dry-run | -n | --delete | -d) exempt=1 ;;
      --tags) tags_only=1 ;;
      -*) ;;
      *) positional=$((positional + 1)) ;;
    esac
  done
  [ "$exempt" = 1 ] && continue
  # --tags alone (or with just a remote) sends tags; with a branch it sends that too.
  [ "$tags_only" = 1 ] && [ "$positional" -le 1 ] && continue

  # The repository the push acts on: `git -C <dir>` (relative to the current directory), else the current directory.
  dir=$(printf '%s' "$segment" | sed -nE "s/.*git[[:space:]]+((-c[[:space:]]+[^[:space:]]+|--?[^[:space:]]+)[[:space:]]+)*-C[[:space:]]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+)).*/\4\5\6/p" | head -1)
  if [ -n "$dir" ]; then dir=$(resolve "$current" "$dir"); else dir=$current; fi

  # The record is made from the whole segment (not the masked words, which hide what is inside quotes),
  # with its spacing collapsed (unquoted on purpose).
  # shellcheck disable=SC2086,SC2116
  judge "$dir" "$(echo $segment)" || blocked=1
done <<EOF
$segments
EOF

# Every push on the line is recorded before this, so one retry of the line goes through.
if [ "$blocked" = 1 ]; then
  cat >&2 <<'EOF'
Blocked once: this commit has not been through the review loop.
Run /code-loops:review-loop on the branch, fix what it finds, then run the same git push again.
If the loop leaves changes uncommitted, tell the user to commit them first; the next push of a new commit asks again.
EOF
  exit 2
fi
exit 0
