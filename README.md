# code-loops

A Claude Code plugin with three skills that check a branch before a pull request.

- `/code-loops:review-loop`: runs `.claude/verify.sh`, reviews the branch diff, fixes the findings, and repeats until a lap finds nothing. A documentation-only diff is checked with `/code-loops:doc-code-consistency` instead. If three laps in a row still find something, it stops and reports what remains. It does not push or open a pull request. `.claude/verify.sh` is optional (`/code-loops:init-verify` creates one); without it, verification is skipped and the report says so.
- `/code-loops:doc-code-consistency`: checks that the documentation (README, `docs/`, `CLAUDE.md`, `CHANGELOG`, comments) matches the code, and reports contradictions, stale text and missing items with file:line evidence. It only reads, and changes files only when you ask it to fix a finding.
- `/code-loops:init-verify`: proposes a fast `.claude/verify.sh` (lint, type check, unit tests the project already defines), shows it, and writes it only after you agree. A non-zero exit means verification failed.

## Install

```bash
claude plugin marketplace add 103kaz/claude-code-loops
claude plugin install code-loops@claude-code-loops
```

## License

MIT
