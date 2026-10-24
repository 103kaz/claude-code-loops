#!/usr/bin/env bash
# PreToolUse hook (Bash): the first `git push` for a given HEAD is blocked with
# a request to run /code-loops:review-loop. The attempt is recorded, so a retry
# of the same HEAD goes through. A new commit asks again.
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

# Quoted strings become "Q", so `git commit -m "git push"` does not match and
# `git -C "my dir" push` does.
masked=$(printf '%s' "$command_line" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g")

push_re='(^|[^[:alnum:]_-])git(([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)|([[:space:]]+--?[^[:space:]]+))*[[:space:]]+push([^[:alnum:]_-]|$)'
printf '%s' "$masked" | grep -Eq "$push_re" || exit 0

# Pushes that do not publish commits. Only the words of the push itself count
# (up to the next ; & |), not other commands on the line.
push_args=$(printf '%s' "$masked" | grep -oE "${push_re}.*" | head -1 | sed -E 's/[;&|].*//; s/^.*[[:space:]]push//')
tags_only=0 positional=0
for word in $push_args; do
  case $word in
    --dry-run | -n | --delete | -d) exit 0 ;;
    --tags) tags_only=1 ;;
    -*) ;;
    *) positional=$((positional + 1)) ;;
  esac
done
# --tags alone (or with just a remote) sends tags; with a branch it sends that too.
[ "$tags_only" = 1 ] && [ "$positional" -le 1 ] && exit 0

# The repository the command acts on: `git -C <dir>`, else `cd <dir>`, else cwd.
dir=$(printf '%s' "$command_line" | sed -nE "s/.*git[[:space:]]+-C[[:space:]]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+)).*/\2\3\4/p" | head -1)
[ -n "$dir" ] || dir=$(printf '%s' "$command_line" | sed -nE "s/(^|.*[;&|][[:space:]]*)cd[[:space:]]+(\"([^\"]*)\"|'([^']*)'|([^[:space:];&|]+)).*/\3\4\5/p" | head -1)
if [ -n "$dir" ]; then
  case $dir in
    /*) cwd=$dir ;;
    *) cwd=$cwd/$dir ;;
  esac
fi

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0
head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null) || exit 0
top=$(git -C "$cwd" rev-parse --show-toplevel)

# Nothing new to push (upstream already has HEAD).
if git -C "$cwd" rev-parse --verify -q '@{u}' >/dev/null 2>&1 &&
  [ "$(git -C "$cwd" rev-list --count '@{u}..HEAD')" = 0 ]; then
  exit 0
fi

state_dir=${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/code-loops}
key=$(printf '%s %s' "$top" "$head" | { shasum || sha1sum || cksum; } 2>/dev/null | cut -d' ' -f1)
[ -n "$key" ] || exit 0
marker=$state_dir/$key
[ -e "$marker" ] && exit 0

if ! { mkdir -p "$state_dir" && : >"$marker"; } 2>/dev/null; then
  echo "code-loops: cannot write $state_dir, so the pre-push review request is skipped." >&2
  exit 0
fi
find "$state_dir" -type f -mtime +30 -delete 2>/dev/null

cat >&2 <<'EOF'
Blocked once: this commit has not been through the review loop.
Run /code-loops:review-loop on the branch, fix what it finds, then run the same git push again.
If the loop leaves changes uncommitted, tell the user to commit them first; the next push of a new commit asks again.
EOF
exit 2
