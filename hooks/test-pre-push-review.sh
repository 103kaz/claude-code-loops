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
# A PATH without jq, to test the fallback that parses the JSON by hand.
mkdir "$work/nojq-bin"
for tool in bash git sed grep cat cut find shasum head mkdir awk; do
  ln -s "$(command -v "$tool")" "$work/nojq-bin/$tool"
done
# check <expected exit> <cwd> <command>; set NOJQ=1 to run the hook without jq
check() {
  local out got input
  input=$(jq -n --arg cwd "$2" --arg c "$3" '{cwd:$cwd,tool_input:{command:$c}}')
  if [ "${NOJQ:-}" = 1 ]; then
    out=$(printf '%s' "$input" | PATH="$work/nojq-bin" bash "$hook" 2>/dev/null)
  else
    out=$(printf '%s' "$input" | "$hook" 2>/dev/null)
  fi
  got=$?
  if [ "$got" = "$1" ]; then echo "ok   ${NOJQ:+(no jq) }$3"; else echo "FAIL ${NOJQ:+(no jq) }$3 (expected $1, got $got) $out"; fail=1; fi
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

# The exemptions look only at the push's own words.
check 0 "$repo" 'git push -d origin x'
check 0 "$repo" 'git push origin --tags'
check 2 "$repo" 'git push origin x && ls -d .'
new_head f
check 2 "$repo" 'git push origin main --tags'
new_head g
check 2 "$repo" 'git push -u origin x; echo -n done'

# Every push on the line is judged, not only the first.
new_head j
check 2 "$repo" 'git push --dry-run origin x; git push origin x'
new_head k
check 2 "$repo" 'git push origin --tags; git push origin x'
# A quoted separator does not start a new command.
new_head l
check 0 "$repo" 'git commit -m "a; git push origin x"'
check 0 "$repo" "echo 'x | git push'"

# The same commit pushed in another way asks again; the same way goes through.
new_head m
check 2 "$repo" 'git push origin x'
check 2 "$repo" 'git push origin y'
check 0 "$repo" 'git push origin y'
check 0 "$repo" 'git push origin x'

# A cd that cannot be followed does not move the directory of the push.
new_head p
check 2 "$repo" '(cd /nonexist; true); git push origin x'
new_head q
check 2 "$repo" 'cd -P /nonexist && git push origin x'
new_head r
# shellcheck disable=SC2016 # the variable is for the hook to see, not for this shell
check 2 "$repo" 'cd "$NOWHERE" && git push origin x'

# Several pushes on one line: one retry of the line goes through.
new_head s
check 2 "$repo" 'git push origin a; git push origin b'
check 0 "$repo" 'git push origin a; git push origin b'

# Words inside quotes tell two pushes apart.
new_head t
check 2 "$repo" 'git push origin "a b"'
check 2 "$repo" 'git push origin "c d"'
check 0 "$repo" 'git push origin "c d"'

# Spacing and a line continuation do not change which push it is.
new_head u
check 2 "$repo" 'git push origin x'
check 0 "$repo" 'git  push   origin x'
new_head n
check 2 "$repo" 'git push origin x'
check 0 "$repo" 'git  push origin   x'
new_head o
check 0 "$repo" 'git push \
  --dry-run origin x'

# ~ in cd is the home directory; -C is read relative to a cd before it.
plain=$work/plain
git init -q "$plain"
git -C "$plain" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
HOME=$work check 2 "$work" 'cd ~/plain && git push origin x'
HOME=$work check 0 "$work" 'cd ~/plain && git push origin x'
git -C "$plain" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
check 2 "$work" 'cd plain && git -C . push origin x'
# The -C of another git command on the line is not the push's.
git -C "$plain" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c
check 2 "$plain" "git -C \"$work\" status && git push origin x"

# Without jq the hook still reads the command out of the JSON.
new_head h
NOJQ=1 check 2 "$repo" 'git push origin x'
NOJQ=1 check 0 "$repo" 'git push origin x'
new_head i
NOJQ=1 check 2 "$work" "git -C \"$repo\" push"
NOJQ=1 check 0 "$repo" "git commit -m 'note git push hook'"
exit $fail
