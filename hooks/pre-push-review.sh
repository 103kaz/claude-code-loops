#!/usr/bin/env bash
# PreToolUse hook (Bash): the first `git push` for a given HEAD is blocked with
# a request to run /code-loops:review-loop. The attempt is recorded together with
# the length of the session transcript at that moment. A retry of the same push
# (same HEAD, same push words) goes through once the transcript shows the review
# loop was run after the block; without a readable transcript the retry goes
# through as it is. A new commit, or a different push of the same commit, asks
# again. Every push on the command line is judged, not only the first.
# It fails open: anything it cannot judge (unknown directory, no way to record
# the attempt) lets the command run.
# The userConfig option pre_push_review (default on) turns the hook off when it is
# false, 0, no or off.

set -f # no globbing when the command's words are split below

input=$(cat)

# Read the input first, so that leaving early does not close the pipe under the caller.
case $(printf '%s' "${CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW:-}" | tr '[:upper:]' '[:lower:]') in
  false | 0 | no | off) exit 0 ;;
esac

if command -v jq >/dev/null 2>&1; then
  command_line=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
else
  # Without jq: pick the string values out of the JSON by hand.
  json_string() {
    printf '%s' "$input" |
      sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 |
      sed -e 's/\\n/ ; /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
  }
  command_line=$(json_string command)
  cwd=$(json_string cwd)
  transcript=$(json_string transcript_path)
fi

# The review loop in a transcript (read from line $2 on): the Skill tool call, or the user's slash command.
# The command text of a Bash call is escaped in the transcript and sits on an assistant line, and a tool
# result carries a tool_use_id, so neither a pushed command nor a file Claude read can pass for the review.
review_ran() {
  local from=$(($1 + 1))
  tail -n +"$from" "$2" 2>/dev/null | grep -Eq '"name":"Skill","input":\{"skill":"(code-loops:)?review-loop"' && return 0
  tail -n +"$from" "$2" 2>/dev/null | grep -E '<command-name>/?code-loops:review-loop' | grep -Ev '"type":"assistant"|tool_use_id' | grep -q .
}
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
  if [ -e "$marker" ]; then
    # Asked before: the marker holds the transcript length and path at that time (empty when there was no transcript).
    asked=$(cat "$marker" 2>/dev/null)
    asked_at=${asked%% *} asked_path=''
    case $asked in *' '*) asked_path=${asked#* } ;; esac
    case $asked_at in '' | *[!0-9]*) return 0 ;; esac
    [ -r "$transcript" ] || return 0
    # Only trust a transcript in the known format (it has assistant messages); an unknown one cannot be judged.
    grep -q '"type":"assistant"' "$transcript" 2>/dev/null || return 0
    # Another session's transcript has its own line numbers: read all of it.
    if [ -n "$asked_path" ] && [ "$asked_path" != "$transcript" ]; then asked_at=0; fi
    review_ran "$asked_at" "$transcript" && return 0
    asked_again=1
    return 1
  fi

  lines=''
  if [ -n "$transcript" ] && [ -r "$transcript" ]; then
    lines="$(wc -l <"$transcript" 2>/dev/null | tr -d '[:space:]') $transcript"
  fi
  if ! { mkdir -p "$state_dir" && printf '%s' "$lines" >"$marker"; } 2>/dev/null; then
    echo "code-loops: cannot write $state_dir, so the pre-push review request is skipped." >&2
    return 0
  fi
  find "$state_dir" -type f -mtime +30 -delete 2>/dev/null
  first_ask=1
  return 1
}

# The -C directories of the git command that runs `push` in one command segment, one per line, in order.
# The words are split like the shell does (quotes removed), and git's own options are skipped, so a
# directory name that holds spaces or the word push is read as one word.
git_c_dirs() {
  printf '%s' "$1" | awk '
    function flush() { if (w != "" || have) tok[++n] = w; w = ""; have = 0 }
    {
      s = $0; q = ""; w = ""; have = 0; n = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; else w = w c; continue }
        if (c == "\047" || c == "\"") { q = c; have = 1; continue }
        if (c == " " || c == "\t") { flush(); continue }
        w = w c
      }
      flush()
      out = ""
      for (i = 1; i <= n; i++) {
        if (tok[i] !~ /(^|\/)git$/) continue
        d = ""; j = i + 1
        while (j <= n) {
          if (tok[j] == "-C") { d = d tok[j + 1] "\n"; j += 2 }
          else if (tok[j] == "-c") j += 2
          else if (tok[j] ~ /^-/) j++
          else break
        }
        if (tok[j] == "push") out = d
      }
      printf "%s", out
    }'
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
  tags_only=0 positional=0 exempt=0 skip_next=0
  for word in $push_args; do
    if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi # the target of a redirection
    case $word in
      --dry-run | -n | --delete | -d) exempt=1 ;;
      --tags) tags_only=1 ;;
      *'>' | *'<') skip_next=1 ;; # a redirection (>, 2>, <) with its target as the next word
      *'>'* | *'<'*) ;; # a redirection with its target attached (>/dev/null)
      -*) ;;
      *) positional=$((positional + 1)) ;;
    esac
  done
  [ "$exempt" = 1 ] && continue
  # --tags alone (or with just a remote) sends tags; with a branch it sends that too.
  [ "$tags_only" = 1 ] && [ "$positional" -le 1 ] && continue

  # The repository the push acts on: the -C options of the git command (each relative to the one before,
  # as git reads them), starting from the current directory.
  dir=$current
  while IFS= read -r c_dir; do
    [ -n "$c_dir" ] && dir=$(resolve "$dir" "$c_dir")
  done <<EOF
$(git_c_dirs "$segment")
EOF

  # The record is made from the whole segment (not the masked words, which hide what is inside quotes),
  # with its spacing collapsed (unquoted on purpose).
  # shellcheck disable=SC2086,SC2116
  judge "$dir" "$(echo $segment)" || blocked=1
done <<EOF
$segments
EOF

# Every push on the line is recorded before this, so one retry of the line goes through.
if [ "$blocked" = 1 ]; then
  if [ "${asked_again:-0}" = 1 ]; then
    echo "Blocked again: /code-loops:review-loop has not been run since the last block." >&2
    echo "Run it on the branch, fix what it finds, then run the same git push again. To push without it, the user can push from a terminal." >&2
  fi
  if [ "${first_ask:-0}" = 1 ]; then
    cat >&2 <<'EOF'
Blocked once: this commit has not been through the review loop.
Run /code-loops:review-loop on the branch, fix what it finds, then run the same git push again.
If the loop leaves changes uncommitted, tell the user to commit them first; the next push of a new commit asks again.
EOF
  fi
  exit 2
fi
exit 0
