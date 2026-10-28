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
- code-guard runs the script only at the end of a turn in which files changed, and only after you approved it. A review that changes nothing, a script you have not approved, or a missing `.claude/verify.sh` means nothing was verified. The report says so; run `.claude/verify.sh` yourself in that case. Approve the script once with code-guard's `trust-verify.sh` before the first review.
- The pre-push hook and code-guard's guards both run on the same `git push`. code-guard blocks a push to a protected branch and asks when `confirm_push` is on; this hook asks for the review. If either blocks, the push does not run.

## Pre-push hook

The plugin also registers a PreToolUse hook on Bash (`hooks/pre-push-review.sh`).

- **What it does.** When Claude runs `git push`, the first attempt for each HEAD commit is blocked with a message asking Claude to run `/code-loops:review-loop` and push again. Every `git push` on the command line is judged and recorded in one go, so one retry of the whole line goes through.
- **What a record is.** The attempt is recorded under `$CLAUDE_PLUGIN_DATA` (default `~/.claude/plugins/data/code-loops`) together with the push's own command (spacing ignored). A new commit, or a different push of the same commit (another branch, other options), asks again, except for the commits that follow a block (below). The record is written when the push is blocked, so a push that code-guard also blocks, or that you decline at its confirmation, still counts as asked for that exact push.
- **When the retry goes through.** The record also holds the length and path of the session transcript at the time of the block. The retry goes through only if the transcript shows `/code-loops:review-loop` (the Skill tool call, or your slash command) after that point; otherwise it is blocked again. A retry from another session (a resumed or cleared one) reads that session's whole transcript. The text of a pushed command or of a file Claude read does not count. It checks that the review was started, not that it found nothing or that no file changed after it. Without a readable transcript (an older Claude Code, a missing path, a format with no assistant messages) the retry goes through as before.
- **Committing the review loop's fixes.** When the fixes are committed after the review, the same push of the new HEAD on the same branch goes through without another block, if the new HEAD descends from the blocked one and the transcript of the session that was blocked shows the review loop after the block. This works once per block: after that push (or after a retry of the blocked HEAD itself goes through), the next new commit asks again. It does not look at what the added commits change, so a merge of the base branch on top counts too. A HEAD that does not descend from the blocked one (after an amend or a rebase), a different push, another branch, another session, a session with no readable transcript, or a blocked HEAD that upstream already has (pushed from a terminal) asks again.
- **To push without the review**, push from a terminal. The hook does nothing for pushes you run yourself there.
- **It does nothing** when upstream already has HEAD, outside a git repository, for `--dry-run`, `-n`, `--delete` and `-d` pushes (judged from the push's own words, not other commands on the line), for `--tags` pushes that name no branch, or when it cannot write the record.
- **Which repository.** It follows `git -C <dir>` and `cd <dir> &&`, but it judges by the HEAD of that repository, not by the refs the push names. A `cd` it cannot follow (an option, a variable, a missing directory, one inside `( )` after the `)`) does not change the directory the push is judged in.
- **To turn it off**, set the plugin option `pre_push_review` to false in the `/plugin` settings screen (the skills stay available), or disable the plugin. The option takes `false`, `0`, `no` or `off`; any other value, or none, leaves the hook on. Turn it off where another rule already asks for the review before a push. `bash hooks/test-pre-push-review.sh` runs its tests (needs `jq` to build the test input; the hook itself also works without it).

## Install

```bash
claude plugin marketplace add https://github.com/103kaz/claude-code-loops.git
claude plugin install code-loops@claude-code-loops
```

The https URL keeps the install from using an SSH key (the `103kaz/claude-code-loops` shorthand clones over SSH when a key is configured).

To use it together with code-guard in one install, see [claude-code-workflow](https://github.com/103kaz/claude-code-workflow).

## License

MIT
