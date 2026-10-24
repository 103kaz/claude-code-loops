#!/usr/bin/env bash
# Tests for pre-push-review.sh. Usage: bash hooks/test-pre-push-review.sh
set -u
hook=$(cd "$(dirname "$0")" && pwd)/pre-push-review.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/pre-push-review.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
export CLAUDE_PLUGIN_DATA=$work/data
repo=$work/my\ repo
git init -q "$repo"
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; }
commit a

fail=0
# check <expected exit> <cwd> <command>
check() {
  local out got
  out=$(jq -n --arg cwd "$2" --arg c "$3" '{cwd:$cwd,tool_input:{command:$c}}' | "$hook" 2>/dev/null)
  got=$?
  if [ "$got" = "$1" ]; then echo "ok   $3"; else echo "FAIL $3 (expected $1, got $got) $out"; fail=1; fi
}
new_head() { commit "$1"; }

check 0 "$repo" 'ls -la'
check 0 "$repo" "git commit -m 'note git push hook'"
check 0 "$repo" 'grep "git push" f'
check 0 "$repo" 'git push --dry-run origin x'
check 0 "$repo" 'git push --delete origin x'
check 0 "$repo" 'git push --tags'
check 2 "$repo" 'git push origin x'
check 0 "$repo" 'git push origin x'
new_head b
check 2 "$work" "git -C \"$repo\" push"
check 0 "$work" "git -C \"$repo\" push"
new_head c
check 2 "$work" "cd \"$repo\" && git push"
new_head d
check 2 "$repo" 'git push'
check 0 "$work" 'git push'
new_head e
CLAUDE_PLUGIN_DATA=/proc/nope/x check 0 "$repo" 'git push'
exit $fail
