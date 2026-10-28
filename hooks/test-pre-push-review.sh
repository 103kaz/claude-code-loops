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
for tool in bash git sed grep cat cut find shasum head mkdir awk wc tail tr; do
  ln -s "$(command -v "$tool")" "$work/nojq-bin/$tool"
done
# check <expected exit> <cwd> <command>; set NOJQ=1 to run the hook without jq
check() {
  local out got input
  input=$(jq -n --arg cwd "$2" --arg c "$3" --arg t "${TRANSCRIPT:-}" '{cwd:$cwd,tool_input:{command:$c}} + (if $t == "" then {} else {transcript_path:$t} end)')
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

# Redirections are not arguments of the push; several -C and a quoted -c value are read.
new_head v
check 0 "$repo" 'git push --tags origin 2>&1'
check 2 "$work" "git -c \"a b=c\" -C \"$work\" -C \"my repo\" push origin x"

# With the transcript, the retry passes only after the review loop was run since the block.
transcript=$work/transcript.jsonl
printf '%s\n' '{"type":"user"}' '{"type":"assistant"}' >"$transcript"
new_head w
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"name":"Bash","input":{"command":"echo \"skill\":\"code-loops:review-loop\""}}' >>"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"tool_use","name":"Skill","input":{"skill":"code-loops:review-loop"}}' >>"$transcript"
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'
# A review before the block does not count; the user's slash command does.
new_head x
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"user","message":"<command-name>/code-loops:review-loop</command-name>"}' >>"$transcript"
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'
# An unreadable transcript path falls back to "the retry goes through".
new_head y
TRANSCRIPT=$work/missing.jsonl check 2 "$repo" 'git push origin x'
TRANSCRIPT=$work/missing.jsonl check 0 "$repo" 'git push origin x'
# A transcript in an unknown format (no assistant messages) cannot be judged: the retry goes through.
new_head aa
printf '%s\n' '{"unknown":"format"}' >"$work/other.jsonl"
TRANSCRIPT=$work/other.jsonl check 2 "$repo" 'git push origin x'
TRANSCRIPT=$work/other.jsonl check 0 "$repo" 'git push origin x'
# The retry is judged on the transcript it comes from: another session's is read from its start.
new_head ab
printf '%s\n' '{"type":"user"}' '{"type":"assistant"}' '{"type":"user"}' '{"type":"assistant"}' '{"type":"user"}' >"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"assistant"}' >"$work/b.jsonl"
TRANSCRIPT=$work/b.jsonl check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"assistant"}' '{"type":"tool_use","name":"Skill","input":{"skill":"code-loops:review-loop"}}' >"$work/b.jsonl"
TRANSCRIPT=$work/b.jsonl check 0 "$repo" 'git push origin x'

# The text of a command, or of a file Claude read, is not the review loop.
new_head ac
printf '%s\n' '{"type":"user"}' '{"type":"assistant"}' >"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"assistant","message":"git push origin x # <command-name>/code-loops:review-loop"}' >>"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"user","tool_use_id":"t1","content":"<command-name>/code-loops:review-loop</command-name>"}' >>"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"tool_use","name":"Skill","input":{"skill":"review-loop"}}' >>"$transcript"
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'

# Commits on top of the blocked HEAD (the review loop's fixes) go through once after the review;
# the commit after that asks again.
review() { printf '%s\n' '{"type":"tool_use","name":"Skill","input":{"skill":"code-loops:review-loop"}}' >>"$transcript"; }
new_head ba
printf '%s\n' '{"type":"user"}' '{"type":"assistant"}' >"$transcript"
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
review
new_head bb
new_head bc
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'
new_head bd
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
# Without the review after the block, the new commit is blocked.
new_head be
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
# A review spent on the retry of the blocked HEAD does not cover the next commit.
new_head bf
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
review
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'
new_head bg
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
# A HEAD that does not descend from the blocked one (amend, rebase) is blocked.
review
git -C "$repo" reset -q --hard HEAD~1
new_head bh
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
# Another push of the descendant (other branch, other options) is not covered.
new_head bi
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
review
new_head bj
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin y'
# Without a transcript the review cannot be seen, so the descendant is blocked.
new_head bk
check 2 "$repo" 'git push origin z'
new_head bl
check 2 "$repo" 'git push origin z'
# The review must be in the session that was blocked; another session's does not count.
new_head bm
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin v'
printf '%s\n' '{"type":"assistant"}' '{"type":"tool_use","name":"Skill","input":{"skill":"code-loops:review-loop"}}' >"$work/c.jsonl"
new_head bn
TRANSCRIPT=$work/c.jsonl check 2 "$repo" 'git push origin v'
# Without jq the same holds.
new_head bo
NOJQ=1 TRANSCRIPT=$transcript check 2 "$repo" 'git push origin w'
review
new_head bp
NOJQ=1 TRANSCRIPT=$transcript check 0 "$repo" 'git push origin w'
# Several pushes on one line: each follows its own block.
new_head bq
TRANSCRIPT=$transcript check 2 "$repo" 'git push origin a1; git push origin b1'
review
new_head br
TRANSCRIPT=$transcript check 0 "$repo" 'git push origin a1; git push origin b1'

# A bare `git push` on another branch does not follow the block of this one.
branched=$work/branched
git init -q "$branched"
bcommit() { git -C "$branched" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; }
bcommit a
TRANSCRIPT=$transcript check 2 "$branched" 'git push'
review
git -C "$branched" switch -q -c other
bcommit b
TRANSCRIPT=$transcript check 2 "$branched" 'git push'
# A blocked HEAD that upstream already has (pushed from a terminal) ends its block.
git init -q --bare "$work/remote.git"
git -C "$branched" remote add origin "$work/remote.git"
bcommit c
TRANSCRIPT=$transcript check 2 "$branched" 'git push'
review
git -C "$branched" push -q -u origin other 2>/dev/null
bcommit d
TRANSCRIPT=$transcript check 2 "$branched" 'git push'
# So does one pushed in another way, with no upstream set.
bcommit e
TRANSCRIPT=$transcript check 2 "$branched" 'git push origin y'
review
TRANSCRIPT=$transcript check 2 "$branched" 'git push origin HEAD:y'
review
TRANSCRIPT=$transcript check 0 "$branched" 'git push origin HEAD:y'
git -C "$branched" push -q origin HEAD:y 2>/dev/null
bcommit f
TRANSCRIPT=$transcript check 2 "$branched" 'git push origin y'

# The target of a redirection is not an argument of the push.
new_head ad
check 0 "$repo" 'git push --tags origin > out.log'

# A directory named with spaces or the word push is one word of -C.
spaced=$work/my\ push\ dir
git init -q "$spaced"
git -C "$spaced" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
check 2 "$work" "git -C \"$spaced\" push origin x"
named=$work/push
git init -q "$named"
git -C "$named" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
check 2 "$work" 'git -C push push origin x'

# The transcript path is read without jq too.
new_head z
printf '%s\n' '{"type":"user"}' '{"type":"assistant"}' >"$transcript"
NOJQ=1 TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
NOJQ=1 TRANSCRIPT=$transcript check 2 "$repo" 'git push origin x'
printf '%s\n' '{"type":"tool_use","name":"Skill","input":{"skill":"code-loops:review-loop"}}' >>"$transcript"
NOJQ=1 TRANSCRIPT=$transcript check 0 "$repo" 'git push origin x'

# The option pre_push_review turns the hook off (false, 0, no, off, any case); on or unset it asks.
new_head pr1
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=false check 0 "$repo" 'git push origin x'
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=OFF check 0 "$repo" 'git push origin x'
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=0 check 0 "$repo" 'git push origin x'
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=no check 0 "$repo" 'git push origin x'
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=true check 2 "$repo" 'git push origin x'
new_head pr1b
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW=garbage check 2 "$repo" 'git push origin x'
new_head pr2
CLAUDE_PLUGIN_OPTION_PRE_PUSH_REVIEW='' check 2 "$repo" 'git push origin x'

# Without jq the hook still reads the command out of the JSON.
new_head h
NOJQ=1 check 2 "$repo" 'git push origin x'
NOJQ=1 check 0 "$repo" 'git push origin x'
new_head i
NOJQ=1 check 2 "$work" "git -C \"$repo\" push"
NOJQ=1 check 0 "$repo" "git commit -m 'note git push hook'"
exit $fail
