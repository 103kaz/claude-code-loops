# code-loops

A Claude Code plugin with three skills that check a branch before a pull request.

- `/code-loops:review-loop`: runs `.claude/verify.sh`, reviews the branch diff, fixes the findings, and repeats until a lap finds nothing. A documentation-only diff is checked with `/code-loops:doc-code-consistency` instead; when the diff changes code that the documentation describes, it runs `/code-loops:doc-code-consistency` once at the end as well. If three laps in a row still find something, it stops and reports what remains. At the end (except for a documentation-only diff) it asks whether to run an independent review, once: a subagent reads only the diff and looks for the inputs and states that break it (default: no; it checks against `.claude/review/checklist.md` if the project has one). It does not push or open a pull request. `.claude/verify.sh` is optional (`/code-loops:init-verify` creates one); without it, verification is skipped and the report says so.
- `/code-loops:doc-code-consistency`: checks that the documentation (README, `docs/`, `CLAUDE.md`, `CHANGELOG`, comments) matches the code, and reports contradictions, stale text and missing items with file:line evidence. It only reads, and changes files only when you ask it to fix a finding.
- `/code-loops:init-verify`: proposes a fast `.claude/verify.sh` (lint, type check, unit tests the project already defines), shows it, and writes it only after you agree. A non-zero exit means verification failed.

## With code-guard

[code-guard](https://github.com/103kaz/claude-code-guard) runs `.claude/verify.sh` itself when Claude ends a response that changed files, and only after the user has approved the script's content. When code-guard is enabled, `/code-loops:review-loop` does not run `.claude/verify.sh` (so it neither skips that approval nor runs the script twice) and leaves verification to code-guard, and `/code-loops:init-verify` points to `/code-guard:setup-verify`. code-guard runs the script only at the end of a turn in which files changed, and only after you approved it, so a review that changes nothing, or a script you have not approved, means nothing was verified. The report says so; run `.claude/verify.sh` yourself in that case.

Without code-guard, `/code-loops:review-loop` runs `.claude/verify.sh` as it is, with no approval step. In a cloned repository that script is someone else's code: read it first. The pre-push hook only asks for a review; it does not stop a push to `main` or a force push. Both skills tell that code-guard is enabled by whether the `/code-guard:setup-verify` skill is available.

## Pre-push hook

The plugin also registers a PreToolUse hook on Bash (`hooks/pre-push-review.sh`). When Claude runs `git push`, the first attempt for each HEAD commit is blocked with a message asking Claude to run `/code-loops:review-loop` and push again. The attempt is recorded under `$CLAUDE_PLUGIN_DATA` (default `~/.claude/plugins/data/code-loops`) together with the push's own command (spacing ignored), so the retry of the same push goes through once the review has been run (see below); a new commit, or a different push of the same commit (another branch, other options), asks again. Every `git push` on the command line is judged and recorded in one go, so one retry of the whole line goes through. A `cd` it cannot follow (an option, a variable, a missing directory, one inside `( )` after the `)`) does not change the directory the push is judged in. The record is written when the push is blocked, so a push that code-guard also blocks, or that you decline at its confirmation, still counts as asked for that exact push. The record also holds the length of the session transcript at the time of the block. The retry goes through only if the transcript shows `/code-loops:review-loop` (the Skill tool call, or your slash command) after that point; otherwise it is blocked again. A retry from another session (a resumed or cleared one) reads that session's whole transcript. The text of a pushed command or of a file Claude read does not count. It checks that the review was started, not that it found nothing or that no file changed after it. Without a readable transcript (an older Claude Code, a missing path, a format with no assistant messages) the retry goes through as before. To push without the review, push from a terminal. It does nothing when upstream already has HEAD, outside a git repository, for `--dry-run`, `-n`, `--delete` and `-d` pushes (judged from the push's own words, not other commands on the line), for `--tags` pushes that name no branch, when it cannot write the record, or for pushes you run yourself in a terminal. It follows `git -C <dir>` and `cd <dir> &&`, but it judges by the HEAD of that repository, not by the refs the push names. To turn it off, set the plugin option `pre_push_review` to false in the `/plugin` settings screen (the skills stay available), or disable the plugin. The option takes `false`, `0`, `no` or `off`; any other value, or none, leaves the hook on. Turn it off where another rule already asks for the review before a push. `bash hooks/test-pre-push-review.sh` runs its tests (needs `jq` to build the test input; the hook itself also works without it).

## Install

```bash
claude plugin marketplace add 103kaz/claude-code-loops
claude plugin install code-loops@claude-code-loops
```

## License

MIT
