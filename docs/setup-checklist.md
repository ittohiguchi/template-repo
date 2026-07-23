# Setup Checklist (phase 1)

Agent-facing. Run once, right after creating a repository from this template
and deciding the language/stack. This is not a health check to repeat at every
agent startup. Rerun only when applying a repository-setting change. Report
each item's result to the user.

## Prerequisites

- Install the local tools: `brew install go-task pre-commit gh jq` or the
  platform equivalent.
- Run `gh auth status` and confirm the authenticated account has repository
  admin permission. Repository rulesets and Actions permissions require it.

## Preinstalled guardrails (do not recreate)

- `.pre-commit-config.yaml`: hygiene hooks, gitleaks (secret detection),
  actionlint + zizmor (GitHub Actions lint/security), workflow schema
  validation, Renovate config validation.
- `.github/workflows/general-pre-commit.yaml`: runs all pre-commit hooks on
  every PR and push to main.
- `.github/workflows/general-secret-scan.yaml`: scans the full git history
  with gitleaks (version pinned to the pre-commit rev) on PRs, pushes to
  main, and weekly.
- `renovate.json5`: dependency updates (GitHub Actions SHAs, pre-commit hook
  revs, language lockfiles) via the Mend Renovate App installed on the org.
- `.gitleaks.toml`: extends the default gitleaks ruleset; add allowlist
  entries there for false positives.
- `Taskfile.yml`: single entry point for dev commands (`task --list`).
- `scripts/init-repo-settings.sh` (`task repo-init`): idempotent GitHub
  repository settings.
- `.github/pull_request_template.md`: captures intent, completion criteria,
  validation, risks, and review questions. The PR body becomes the default
  squash-commit body.
- `sandbox/` / `apps/` / `infra/`: phase-model directories (see `CLAUDE.md`).

## Checklist

1. Run `task repo-init`.
   Verify the Renovate App covers this repository — it is installed at the
   organization level for all repositories: <https://github.com/apps/renovate>.
2. Establish the project commands: lint, format, typecheck, test, build.
   Add each as a task in `Taskfile.yml` with a `desc:`, and hang them under
   the `check` parent task so `task check` stays the full verification suite.
3. Create the CI orchestrator `.github/workflows/ci.yaml`:
   - Trigger on pull requests to `main`.
   - Detect changed paths (e.g. `dorny/paths-filter`, SHA-pinned) and run only
     the affected language jobs; gate heavy suites (integration/e2e) on the
     paths that actually feed them.
   - Jobs run the same `task` targets developers use locally (install task
     via a SHA-pinned setup action).
   - As the repo grows, split reusable workflows named `{lang}-{what}.yaml`
     and keep `ci.yaml` as the orchestrator.
   - Document the workflow architecture and "how to add a language" in
     `.github/workflows/README.md`.
   - Then rerun `task repo-init -- --checks pre-commit,gitleaks,ci` to make
     the `ci` check required.
4. Add language-specific lint/format hooks to `.pre-commit-config.yaml`.
5. Update `.env.example` with the real variable names (placeholder values
   only; never real values).
6. Run `task setup` locally to install the pre-commit git hook.
7. Replace the description at the top of `CLAUDE.md` with a one-paragraph
   project description. Keep every other section; the repository starts in
   the exploration phase — work in `sandbox/`.
8. After the real maintainers and repository visibility are known:
   - Add `.github/CODEOWNERS` with actual users or teams; do not commit
     placeholder owners.
   - Before accepting external users or contributions, add a Japanese
     `SECURITY.md` with the supported versions and a private reporting route.
