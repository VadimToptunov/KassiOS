---
description: Implement a KassiOS change end-to-end — build, self-review, test, then open a PR (never merges).
argument-hint: <what to build or fix>
allowed-tools: Read, Bash(git *), Bash(gh *)
---

Ship this change to KassiOS: **$ARGUMENTS**

Follow these steps in order and do not skip any:

1. **Branch.** From the latest main:
   `git checkout main && git pull --ff-only origin main && git checkout -b <short-slug>`.
2. **Build.** Delegate the implementation to the **swift-builder** subagent.
   Give it the change description and let it write the code.
3. **Review.** Delegate to the **kass-reviewer** subagent. Apply every valid
   finding (send them back to swift-builder to fix). Repeat until the reviewer
   is clean.
4. **Test.** Delegate to the **test-runner** subagent. Do not continue until
   unit **and** integration tests are green. If red, fix via swift-builder and
   re-run.
5. **Changelog.** Add a bullet under `[Unreleased]` in `CHANGELOG.md`.
6. **PR.** Commit, `git push -u origin <branch>`, and open a PR with
   `gh pr create` (concise title + body listing the change and the verification).
   **Do NOT merge** — `main` is protected; the human merges once CI is green.

Report the PR URL and a one-line summary of what shipped.
