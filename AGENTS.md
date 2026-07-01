# AGENTS.md

Guide for AI coding agents working in this repository.

## Agent Operating Rules

- **Allowed:** Edit configuration, manifests, scripts, and documentation; run local dry-runs and linting; read the codebase and GitHub state.
- **Ask first:** Pushing commits to any branch (including feature branches), rewriting pushed history, edits under `.github/` or to `OWNERS`, dependency upgrades. When asking, propose the specific change and the reason in one message; do not start the work in the same turn.
- **Never, without explicit per-turn authorization:** Public actions under the user's identity: GitHub comments, reviews, reactions, PR state changes, label or reviewer assignment, posts to Slack or any external surface. Draft such replies as quoted text for the user to send. Authorization is per-action and does not carry between actions or to sub-agents.

## Working in the Codebase

- State your interpretation before making changes. When the task has multiple valid reads, ask; don't pick one silently. For clear failure signals (logs, rendering failures, reproducer), act; the ask rule is about unclear requirements, not unclear bugs.
- Define success as a checkable outcome: e.g., "add validation" becomes "write validation to helper script, then run it with invalid inputs to confirm it fails". Where the issue is reproducible, the local verification command (e.g. kustomize dry-run or script execution) is the success criterion.
- Before changing or extending a component (like a guide or helper script), read an analogous one in the repository. The closest existing implementation is the canonical pattern; follow its structure, naming, and configuration patterns rather than introducing new conventions.
- Verify behavior against the actual configuration and scripts, not from filenames or familiarity. Run the linting scripts or render the Kustomize manifests when uncertain.
- Do not claim work is complete without running local verification and confirming the relevant output. "Dry-run/Linter passes" is a claim, not a fact, until the command output exists.

## Conventions to Follow

### Commit Requirements

Every commit **must** include a DCO sign-off line:
```
Signed-off-by: Your Name <you@example.com>
```
Add it automatically with `git commit -s`. PRs without DCO sign-off will be blocked by CI.

### Proposals for New Features

Changes that introduce new public APIs, new components, or cross-cutting behavior require a project proposal markdown file at `docs/proposals/<descriptive-name>.md` using the template at `docs/proposals/PROPOSAL_TEMPLATE.md`. Do not open implementation PRs for such changes without an approved proposal.

Bug fixes and small targeted changes do not require a proposal.

### Experimental vs. Core

- Experimental features must be **off by default** and clearly labeled as experimental in docs and any flag names (e.g., `--experimental-*`).
- Experimental guides live in a clearly marked section of `guides/README.md`.
- Do not graduate an experimental feature to stable without maintainer sign-off.

## CI / Testing

There is no local unit test suite to run. Verification is done via:

1. **Kustomize dry-run** (`ci-kustomize-dry-run.yaml`) — validates all kustomize overlays render without error.
2. **Pre-commit linting** — env var linting, typo checking, Dockerfile linting. Run hooks manually via `pre-commit run --all-files` if the hook tooling is installed.
3. **Nightly e2e** — runs full deployment tests on real clusters (GKE, OpenShift, CoreWeave). These are not runnable locally.

For any PR, CI checks that matter are `ci-pr-checks.yaml` and `ci-kustomize-dry-run.yaml`. Make sure these pass.

## What Agents Should and Should Not Do

**Do:**
- Edit `README.md` files in guides to fix accuracy, improve clarity, or update version numbers.
- Update Helm values files (`values.yaml`, `values-*.yaml`) in `guides/*/router/` and `guides/*/modelserver/`.
- Update Kustomize overlays (`kustomization.yaml`, patch files) in guide directories.
- Keep code blocks in guides consistent when environment variables or version pins change.

**Do not:**
- Commit without a DCO sign-off (`git commit -s`).
- Remove or rename environment variables exported in guide `README.md` files without updating every downstream reference in the same guide.
- Introduce new Docker base images or add external dependencies without maintainer discussion.
- Mark experimental guides as stable without approval.
- Break the kustomize dry-run — always check that `kubectl kustomize` succeeds on any overlay you touch.
- Add speculative error handling or defensive abstractions not required by the immediate task.


## Code style

- Comments are terse and only present when the WHY is non-obvious. Never paraphrase the code.
- Docs and comments describe the current state on its own terms. No "previously", "now", "recently", "renamed from", "added to fix", or other temporal or conversational framing. A reader with no context for the change must still understand the text.
- State each fact once, in its canonical location. Do not duplicate across struct docs, prose, tables, inline comments, and examples.
- Do not use Unicode symbols or special characters in general, unless explicitly requested.

## Writing Nightly E2E Tests

Nightly tests live in `.github/workflows/nightly-e2e-<guide-name>-<platform>.yaml`. For details on file naming, minimal templates, cron scheduling, and platform-specific fields, refer to the [Nightly E2E Tests Guide](docs/nightly-e2e.md).
