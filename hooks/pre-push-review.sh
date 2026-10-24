#!/usr/bin/env bash
# PreToolUse hook (Bash): the first `git push` for a given HEAD is blocked with
# a request to run /code-loops:review-loop. The attempt is recorded, so a retry
# of the same HEAD goes through. A new commit asks again.

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  command_line=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
else
  command_line=$input
  cwd=
fi
[ -n "$cwd" ] || cwd=$PWD

push_re='(^|[^[:alnum:]_-])git(([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)|([[:space:]]+--?[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)'
printf '%s' "$command_line" | grep -Eq "$push_re" || exit 0

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0
head=$(git -C "$cwd" rev-parse HEAD 2>/dev/null) || exit 0
top=$(git -C "$cwd" rev-parse --show-toplevel)

# Nothing new to push (upstream already has HEAD).
if git -C "$cwd" rev-parse --verify -q '@{u}' >/dev/null 2>&1 &&
  [ "$(git -C "$cwd" rev-list --count '@{u}..HEAD')" = 0 ]; then
  exit 0
fi

state_dir=${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/code-loops}
key=$(printf '%s %s' "$top" "$head" | shasum | cut -d' ' -f1)
marker=$state_dir/$key
[ -e "$marker" ] && exit 0

mkdir -p "$state_dir" && : >"$marker"

cat >&2 <<'EOF'
Blocked once: this commit has not been through the review loop.
Run /code-loops:review-loop on the branch, fix what it finds, then run the same git push again.
If the loop leaves changes uncommitted, tell the user to commit them first; the next push of a new commit asks again.
EOF
exit 2
