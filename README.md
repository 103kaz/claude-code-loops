# code-loops

A Claude Code plugin with three skills that check a branch before a pull request.

- `/code-loops:review-loop`: runs `.claude/verify.sh`, reviews the branch diff, fixes the findings, and repeats until a lap finds nothing. A documentation-only diff is checked with `/code-loops:doc-code-consistency` instead; when the diff changes code that the documentation describes, it runs `/code-loops:doc-code-consistency` once at the end as well. If three laps in a row still find something, it stops and reports what remains. At the end (except for a documentation-only diff) it asks whether to run an independent review, once: a subagent reads only the diff and looks for the inputs and states that break it (default: no; it checks against `.claude/review/checklist.md` if the project has one). It does not push or open a pull request. `.claude/verify.sh` is optional (`/code-loops:init-verify` creates one); without it, verification is skipped and the report says so.
- `/code-loops:doc-code-consistency`: checks that the documentation (README, `docs/`, `CLAUDE.md`, `CHANGELOG`, comments) matches the code, and reports contradictions, stale text and missing items with file:line evidence. It only reads, and changes files only when you ask it to fix a finding.
- `/code-loops:init-verify`: proposes a fast `.claude/verify.sh` (lint, type check, unit tests the project already defines), shows it, and writes it only after you agree. A non-zero exit means verification failed.

## Using it alone

- `/code-loops:review-loop` runs `.claude/verify.sh` as it is, with no approval step. In a cloned repository that script is someone else's code: read it before running the loop.
- The pre-push hook (below) only asks for a review. It does not stop a push to `main`, a force push or a deleting push, and it does not read secrets or guard anything else. For that, add [code-guard](https://github.com/103kaz/claude-code-guard).
- The hook checks that the review was started, not that it found nothing.

## With code-guard

[code-guard](https://github.com/103kaz/claude-code-guard) runs `.claude/verify.sh` itself when Claude ends a response that changed files, and only after the user has approved the script's content. Both skills tell that code-guard is enabled by whether the `/code-guard:setup-verify` skill is available. When it is:

- `/code-loops:review-loop` does not run `.claude/verify.sh` (so it neither skips that approval nor runs the script twice) and leaves verification to code-guard. `/code-loops:init-verify` points to `/code-guard:setup-verify`.
- code-guard runs the script only at the end of a turn in which files changed, and only after you approved it. A review that changes nothing, a script you have not approved, or a missing `.claude/verify.sh` means nothing was verified. The report says so; run `.claude/verify.sh` yourself in that case. The same holds when the effective `disableAllHooks` value is true (it follows settings precedence, and managed settings can set it too): the skill is still available, but code-guard's verify loop does not run, and the report does not notice. Approve the script once with code-guard's `trust-verify.sh` before the first review.
- The pre-push hook and code-guard's guards both run on the same `git push`. code-guard blocks a push to a protected branch and asks when `confirm_push` is on; this hook asks for the review. If either blocks, the push does not run.

## Pre-push hook

The plugin also registers a PreToolUse hook on Bash (`hooks/pre-push-review.sh`).

- **What it does.** When Claude runs `git push`, the first attempt for each HEAD commit is blocked with a message asking Claude to run `/code-loops:review-loop` and push again. The retry goes through only if the session transcript shows the review loop (the Skill tool call, or your slash command) since the block. It checks that the review was started, not that it found nothing or that no file changed after it. Without a readable transcript the retry goes through.
- **What asks again.** A new commit, or a different push of the same commit (another branch, other options). The exception is the commits that add the review loop's fixes on top of the blocked HEAD: in the same session and on the same branch, that push goes through once. The record is written when the push is blocked, so a push that code-guard also blocks still counts as asked.
- **To push without the review**, push from a terminal. The hook does nothing for pushes you run yourself there.
- **It does nothing** when upstream already has HEAD, outside a git repository, for `--dry-run`, `-n`, `--delete`, `-d` and `--tags`-only pushes, or when it cannot write the record. It follows `git -C <dir>` and `cd <dir> &&` and judges by the HEAD of that repository; a `cd` it cannot follow does not change the directory.
- **To turn it off**, set the plugin option `pre_push_review` to false in the `/plugin` settings screen (the skills stay available), or disable the plugin. The option takes `false`, `0`, `no` or `off`. Turn it off where another rule already asks for the review before a push.
- **Details and tests.** The record lives under `$CLAUDE_PLUGIN_DATA` (default `$CLAUDE_CONFIG_DIR/plugins/data/code-loops`, or `~/.claude/plugins/data/code-loops`). The rules for the fixes' grace are in the comment at the top of `hooks/pre-push-review.sh`. `bash hooks/test-pre-push-review.sh` runs the tests (needs `jq` to build the test input; the hook itself also works without it).

## Install

```bash
claude plugin marketplace add https://github.com/103kaz/claude-code-loops.git
claude plugin install code-loops@claude-code-loops
```

The https URL keeps the install from using an SSH key (the `103kaz/claude-code-loops` shorthand clones over SSH when a key is configured).

To use it together with code-guard in one install, see [claude-code-workflow](https://github.com/103kaz/claude-code-workflow).

## License

MIT
