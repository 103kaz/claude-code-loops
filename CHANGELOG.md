# Changelog

## 0.3.2

- The pre-push hook judges every `git push` on the command line, not only the first (`git push --dry-run ...; git push ...` was let through).
- The hook records the push words with the HEAD, so a different push of the same commit (for example one that code-guard blocked first) still asks for the review.
- The hook reads `cd ~/dir` and a `git -C` that belongs to the push itself, not one of another git command on the line. A `cd` that cannot be followed (`cd -P x`, `cd "$DIR"`, a missing directory, a subshell) no longer moves the directory the push is judged in.
- Several pushes on one line are recorded together, so one retry of the line goes through. The record is made from the whole command, so pushes that differ only inside quotes ask separately.
- The retry of a blocked push goes through only after the session transcript shows `/code-loops:review-loop` was run since the block (the Skill tool call or the user's slash command, not the text of a command or of a file); otherwise it is blocked again. A retry from another session reads that session's whole transcript. Without a readable transcript, or one in an unknown format, it behaves as before.
- A `-C` directory that holds spaces or the word `push` is read as one word; the redirection target in `git push --tags origin > out.log` is not counted as an argument. When one line holds several pushes, each block message is shown.
- Redirections (`2>&1`, `>/dev/null`) are no longer counted as arguments of the push (`git push --tags origin 2>&1` is a tags-only push). Several `-C` options and a quoted `-c` value before `push` are read, so the hook judges the repository git acts on.
- `/code-loops:review-loop` no longer reports verification as done when code-guard does the verifying: code-guard runs only after a turn that changed files and only for an approved `.claude/verify.sh`.

## 0.3.1

- With code-guard enabled, `/code-loops:review-loop` no longer runs `.claude/verify.sh` itself and leaves it to code-guard's verify loop, which runs only an approved script. `/code-loops:init-verify` points to `/code-guard:setup-verify`.

## 0.3.0

- A PreToolUse hook blocks the first `git push` from Claude for each HEAD commit and asks Claude to run `/code-loops:review-loop` first. The retry of the same HEAD goes through; a new commit asks again.

## 0.2.0

- `/code-loops:review-loop` asks at the end whether to run an independent review of the diff (a subagent that reads only the diff). It uses `.claude/review/checklist.md` when the project has one.

## 0.1.0

- First version: `/code-loops:review-loop`, `/code-loops:doc-code-consistency` and `/code-loops:init-verify`.
