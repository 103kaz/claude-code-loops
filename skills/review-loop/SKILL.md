---
name: review-loop
description: Review and fix the current branch's diff before a push or pull request - verify, review, fix, repeat until a lap finds nothing. Use when asked to review-loop, or before opening a pull request.
---

# review-loop

Run the develop loop over the current branch: verify, review the diff, fix, and repeat until a lap finds nothing. The scope is the diff only, not the whole codebase. This skill does not push or open a pull request; those stay with the user.

## Steps

1. Run `.claude/verify.sh`. If it fails, fix that first. If the file does not exist, tell the user and point to `/code-loops:init-verify`, then go on without verification and say so in the report.
   - If the code-guard plugin is enabled (the `/code-guard:setup-verify` skill is available), do not run `.claude/verify.sh` yourself. code-guard's verify loop runs it when you end a response that changed files, and only while the user has approved its content; running it here would skip that approval. Point to `/code-guard:setup-verify` instead of `/code-loops:init-verify`, and say in the report that verification was left to code-guard.
2. Decide the diff. First lap: the branch against its base (`git diff origin/HEAD...HEAD`, plus `git diff HEAD` for uncommitted changes, plus the untracked files from `git status --short`, which you read directly). If `origin/HEAD` is not set, try `origin/main` or `origin/master`; if neither exists, ask the user for the base. If the diff is empty (for example you are on the base branch itself), report that there is nothing to review and stop. If uncommitted changes look unrelated to the branch's work, do not fix them; mention them in the report. Later laps: only what you changed in the previous lap.
3. Review the diff.
   - If it changes code, use the `code-review` skill at medium effort. If that skill is not available, read the diff yourself for bugs: wrong results, missing error paths, and callers the change breaks.
   - If it changes only documentation (`.md` and similar), use `/code-loops:doc-code-consistency` on the diff instead.
4. Fix the findings. Do not commit; leave that to the user. After each fix, go back to step 1. Repeat until a lap finds nothing. A finding you decide not to fix gets a one-line reason. If three laps in a row still turn up findings (a `verify.sh` failure counts, including one that code-guard sends back), stop and report what remains instead of going on.
5. If the diff changed code that the documentation describes, run `/code-loops:doc-code-consistency` on the diff once at the end and fix what it finds.
6. Offer an independent review, once, unless the diff is documentation only. Ask the user (AskUserQuestion) whether to run it, with a one-line note on whether this diff looks worth it (size, risky areas); the default is no. If yes, start a subagent that sees only the diff, not how it was built. Use a read-only agent type if one exists (for example `Explore`); otherwise tell it not to edit files. Have it look for the inputs, states and orderings that break the change, and report each with file:line evidence; if `.claude/review/checklist.md` exists, have it check against that too. Fix what it finds, then run steps 1 and 3 on those fixes only. If subagents are not available, skip this step and say so in the report.
7. Report in a few lines: "Result: no findings", or "Result: findings kept" with each finding and its reason. Add whether `verify.sh` passed, how many laps it took, and whether an independent review ran.

Keep each lap quiet: read the diff, not the repository, and do not repeat the findings of an earlier lap.
