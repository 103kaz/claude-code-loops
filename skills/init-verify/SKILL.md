---
name: init-verify
description: Create .claude/verify.sh for the review-loop skill's verify step. Use when asked to set up or fix the verify loop.
---

# init-verify

Propose a fast `.claude/verify.sh`, show it, and write it only after the user agrees. Keep reads small: this skill should cost few tokens.

If the code-guard plugin is enabled (the `/code-guard:setup-verify` skill is available), use `/code-guard:setup-verify` instead: it also tells the user how to approve the script, which code-guard needs before it runs it.

## Steps

1. List the project root once (names only). Read at most the build files that exist: `package.json` (the `scripts` block only), `pyproject.toml`, `go.mod`, `Cargo.toml`, `Makefile`. Do not read source files or CI logs.
2. If `.claude/verify.sh` exists, read it and propose a diff instead of a rewrite.
3. Pick only checks that finish in seconds: lint, type check, unit tests, using commands the project already defines. Leave slow suites out and say so.
4. Draft the script (`set -euo pipefail`, `cd "$(dirname "$0")/.."`, one line per check, no echo noise: a failure's output goes back to Claude, so quiet commands are cheaper). A non-zero exit means the verification failed.
5. Show the script and which checks were left out, then ask. Write it only after a yes.
6. Run it once and report the result and the time. If nothing can be verified quickly, say so; do not write a script that always passes.
