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
- `.github/workflows/general-pr-fast.yaml`: runs pre-commit hooks only for the
  PR diff. Its `pr-fast` job is the stable required check.
- `.github/workflows/general-main-verification.yaml`: runs `task check` for
  each surviving `main` commit, records `release/main-verification` on the
  exact SHA, and maintains one failure issue.
- `.github/workflows/general-secret-scan.yaml`: scans full git history on
  pushes to `main`, manual revalidation, and weekly runs. It records
  `release/secret-scan` on the exact SHA.
- `renovate.json5`: dependency updates (GitHub Actions SHAs, pre-commit hook
  revs, language lockfiles) via the Mend Renovate App installed on the org.
- `.gitleaks.toml`: extends the default gitleaks ruleset; add allowlist
  entries there for false positives.
- `Taskfile.yml`: single entry point for dev commands (`task --list`).
- `scripts/init-repo-settings.sh` (`task repo-init`): capability-aware,
  idempotent GitHub repository settings. Its first run records the owner type,
  plan, visibility, ruleset availability, PR checks, and release statuses in
  `.github/repository-policy.json`.
- `.github/pull_request_template.md`: captures intent, completion criteria,
  validation, risks, and review questions. The PR body becomes the default
  squash-commit body.
- `sandbox/` / `apps/` / `infra/`: phase-model directories (see `CLAUDE.md`).

## Checklist

1. Run `task repo-init`. The first run probes GitHub once and creates
   `.github/repository-policy.json`; commit that generated policy with the
   scaffold changes. Repeated runs apply the saved policy without probing
   capability again. Run `task repo-init -- --refresh-policy` only after an
   explicitly requested plan or visibility change.
   Confirm that public repositories have secret scanning and push protection
   enabled, while private repositories report both settings as disabled.
   Confirm that repositories with ruleset support record `enforced`, while a
   GitHub Free private repository records `advisory` and completes setup
   without branch protection. Authentication, permission, network, and
   unexpected API failures must still stop setup before settings are changed.
   Verify the Renovate App covers this repository — it is installed at the
   organization level for all repositories: <https://github.com/apps/renovate>.
2. Establish the project commands: lint, format, typecheck, test, build.
   Add each as a task in `Taskfile.yml` with a `desc:`. Keep `task check` as
   the complete production verification suite. Define separate changed-scope
   task targets for fast lint, type checks, and tests that agents can run
   locally before a PR and that `general-pr-fast.yaml` can select by path.
   Keep commit hooks deterministic and fast; do not attach full builds,
   integration tests, or e2e suites to pre-commit.
   For iOS projects with Simulator runtime tests, establish lifecycle
   ownership during this bootstrap:
   - Make automated runtime tests ephemeral-only: create a new Simulator for
     each invocation and delete that exact UDID on every exit path. Never
     discover or reuse an existing device, and never use broad cleanup such as
     `simctl shutdown all`. Interactive Xcode sessions stay outside this task.
   - Serialize the top-level runtime-test task across Git worktrees. Store its
     owner PID, process group, repository root, generated device name, and UDID
     in the Git common directory so the record survives worktree deletion.
   - Start each external phase in a dedicated process group. Bound Simulator
     creation, boot, and boot readiness separately; also bound `xcodebuild` by
     both output inactivity and total elapsed time. Keep every limit easy to
     override through task variables.
   - On normal exit, `INT`, or `TERM`, stop only the owned process group and
     delete only the recorded UDID. On the next invocation, recover the same
     resources after a trapless termination such as `SIGKILL`, but only after
     matching the persisted ownership record to live state. Fail safely when
     ownership cannot be verified.
   - Add contract tests for success, test failure, interruption, each timeout,
     cleanup failure, concurrent execution, trapless stale-resource recovery,
     process descendants, and repeated clean runs. Keep this executable task
     contract as the source of truth instead of duplicating it in
     repository-specific agent instructions.
3. Extend `.github/workflows/general-pr-fast.yaml` for the selected stack:
   - Keep `pull_request` to `main` as its only automatic trigger.
   - Detect changed paths with a SHA-pinned action or an equivalent local
     script and run only affected fast task targets.
   - Keep the stable `pr-fast` job as the only required project check. It must
     report success even when no project path is affected.
   - Target completion within five minutes. Move full builds, complete test
     suites, integration tests, and e2e tests to `task check` when the target
     is exceeded.
   - Split reusable workflows named `{lang}-{what}.yaml` only when the
     orchestrator remains easier to understand than one job.
   - Document the resulting workflow in `.github/workflows/README.md`.
4. Extend `general-main-verification.yaml` so `task check` covers every
   production build and complete test suite. Keep manual `git_ref`
   revalidation for an older `main` commit. Do not make its status a PR
   required check.
5. Add only fast language-specific lint/format hooks to
   `.pre-commit-config.yaml`.
6. Update `.env.example` with the real variable names (placeholder values
   only; never real values).
7. Run `task setup` locally to install the pre-commit git hook.
8. Replace the description at the top of `CLAUDE.md` with a one-paragraph
   project description. Keep every other section; the repository starts in
   the exploration phase — work in `sandbox/`.
9. After the real maintainers and repository visibility are known:
   - Add `.github/CODEOWNERS` with actual users or teams; do not commit
     placeholder owners.
   - Before accepting external users or contributions, add a Japanese
     `SECURITY.md` with the supported versions and a private reporting route.
