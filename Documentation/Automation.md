# Automation: agents, `/ship`, and PR review

Two layers, kept separate.

## Local — Claude Code subagents (on your Mac)

Committed under `.claude/agents/`. Each runs in its own context and returns only
its result, so the reviewer looks with fresh eyes:

- **`swift-builder`** — full tools; writes Swift and runs the build/tests.
- **`kass-reviewer`** — read-only (no Write/Edit); applies the `CLAUDE.md`
  checklist to the diff. It physically cannot change code.
- **`test-runner`** — Bash only; runs unit + integration tests, reports pass/fail.

`swift-builder` is told to call `kass-reviewer` before reporting done, so review
happens *before* you open the diff.

### `/ship`

`.claude/commands/ship.md` chains them end-to-end:

```
/ship add a tabBar.select(_:) helper to KassScreen
```

→ branch → build → self-review → test → CHANGELOG → open PR. It never merges;
`main` is protected and the human merges once CI is green.

## Repository — Claude Code Action (review in PRs)

`.github/workflows/claude-review.yml` (auto-review on every PR) and
`.github/workflows/claude.yml` (interactive `@claude` in comments) use the
official `anthropics/claude-code-action@v1`.

**Both are opt-in and skipped by default** (so they never show a red X):

1. Add an `ANTHROPIC_API_KEY` secret — run `/install-github-app` from the Claude
   Code terminal (it installs the GitHub App and adds the secret), or add it
   manually in **Settings ▸ Secrets and variables ▸ Actions**.
2. Set a repository **variable** `CLAUDE_ENABLED = true` in the same place.

Notes:
- The auto-review job is **not** a required status check — it comments, it
  doesn't gate merges. Required checks stay SwiftLint + unit + UI.
- On PRs from forks GitHub withholds secrets, so auto-review runs only on
  same-repo PRs.
- Auto-review is a first pass on mechanics, **not** a merge gate. Keep API/design
  decisions with a human — that's where the real value is.
