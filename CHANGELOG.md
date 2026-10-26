# Changelog

## Unreleased

- With code-guard enabled, `/code-loops:review-loop` no longer runs `.claude/verify.sh` itself and leaves it to code-guard's verify loop, which runs only an approved script. `/code-loops:init-verify` points to `/code-guard:setup-verify`.

## 0.3.0

- A PreToolUse hook blocks the first `git push` from Claude for each HEAD commit and asks Claude to run `/code-loops:review-loop` first. The retry of the same HEAD goes through; a new commit asks again.

## 0.2.0

- `/code-loops:review-loop` asks at the end whether to run an independent review of the diff (a subagent that reads only the diff). It uses `.claude/review/checklist.md` when the project has one.

## 0.1.0

- First version: `/code-loops:review-loop`, `/code-loops:doc-code-consistency` and `/code-loops:init-verify`.
