# code-loops

A Claude Code plugin with three skills that check a branch before a pull request.

- `/code-loops:review-loop`: runs `.claude/verify.sh`, reviews the branch diff, fixes the findings, and repeats until a lap finds nothing. A documentation-only diff is checked with `/code-loops:doc-code-consistency` instead. If three laps in a row still find something, it stops and reports what remains. At the end (except for a documentation-only diff) it asks whether to run an independent review, once: a subagent reads only the diff and looks for the inputs and states that break it (default: no; it checks against `.claude/review/checklist.md` if the project has one). It does not push or open a pull request. `.claude/verify.sh` is optional (`/code-loops:init-verify` creates one); without it, verification is skipped and the report says so.
- `/code-loops:doc-code-consistency`: checks that the documentation (README, `docs/`, `CLAUDE.md`, `CHANGELOG`, comments) matches the code, and reports contradictions, stale text and missing items with file:line evidence. It only reads, and changes files only when you ask it to fix a finding.
- `/code-loops:init-verify`: proposes a fast `.claude/verify.sh` (lint, type check, unit tests the project already defines), shows it, and writes it only after you agree. A non-zero exit means verification failed.

## Pre-push hook

The plugin also registers a PreToolUse hook on Bash (`hooks/pre-push-review.sh`). When Claude runs `git push`, the first attempt for each HEAD commit is blocked with a message asking Claude to run `/code-loops:review-loop` and push again. The attempt is recorded under `$CLAUDE_PLUGIN_DATA` (default `~/.claude/plugins/data/code-loops`), so the retry of the same HEAD goes through; a new commit asks again. The hook does not check that the review actually ran. It does nothing when upstream already has HEAD, outside a git repository, for `--dry-run`, `--delete` and `--tags` pushes, when it cannot write the record, or for pushes you run yourself in a terminal. It follows `git -C <dir>` and `cd <dir> &&`, but it judges by the HEAD of that repository, not by the refs the push names. To turn it off, disable the plugin. `bash hooks/test-pre-push-review.sh` runs its tests (needs `jq`).

## Install

```bash
claude plugin marketplace add 103kaz/claude-code-loops
claude plugin install code-loops@claude-code-loops
```

## License

MIT
