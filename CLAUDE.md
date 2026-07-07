# Template Repository

GitHub template repository: language-agnostic guardrails only.
Language-specific tooling is added per project via the checklists below.

## Authority

- This file is the top-level source of truth. If any document under `docs/`
  conflicts with it, this file wins.
- When the user announces a rule change, update the implementation, this file,
  and the related documents in the same change set.
- A rule that gets violated repeatedly must be promoted from prose to an
  executable check (pre-commit hook, lint rule, semgrep rule, import contract,
  or script). Prose is a staging area, not an enforcement mechanism.

## Phase model

The phase boundary is a directory, not the repository:

- `sandbox/` — exploration zone: spikes, scratch scripts, throwaway
  prototypes. Architecture and naming rules never apply here; optimize for
  iteration speed. Secret detection and pre-commit hygiene still apply.
- `apps/` — production code, one directory per deployable component
  (`apps/backend`, `apps/frontend`, ...).
- `infra/` — IaC for the shared cloud environments (staging / prod).

A repository starts in the **exploration** phase: work in `sandbox/`. When
the user declares the repository is becoming a **product**, run
`docs/product-checklist.md`; from then on DDD + hexagonal architecture and
executable dependency contracts apply to everything under `apps/`, and code
graduates from `sandbox/` into `apps/` by being restructured to conform.
`sandbox/` stays available for exploration afterwards.

## Checklists

- `docs/setup-checklist.md` — run once, right after creating a repository from
  this template.
- `docs/product-checklist.md` — run when the repository graduates to a product.

## Repository conventions

- `CLAUDE.md` is canonical; `AGENTS.md` is a committed symlink to it.
  `.claude/skills/` is canonical; `.agents/skills` is a committed symlink.
  Never replace a symlink with a regular file.
- All dev commands (setup, lint, format, typecheck, test, build) go through
  `Taskfile.yml`. Discover them with `task --list`. CI jobs must run the same
  task targets developers run locally.
- Branch model: single `main`. All PRs target `main`. Production releases are
  immutable annotated tags `prod-YYYY.MM.DD-NN` on commits reachable from
  `main`; retries and rollbacks cut a new tag, never move one.
- Pin GitHub Actions to a full commit SHA with a version tag comment.
- Dependency updates are Renovate's job (`renovate.json5`): GitHub Actions
  SHAs, pre-commit hook revs, and language lockfiles. Do not add dependabot
  config or custom update workflows.
- Repository settings (branch ruleset, secret scanning, permissions) are
  applied with `task repo-init`, which must stay idempotent.
- Workflow files follow `{prefix}-{what}.yaml` naming (`general-pre-commit`,
  `python-lint`, `terraform-apply`). Conventions and the orchestrator pattern
  are documented in `.github/workflows/README.md`.

## Writing

- Human-facing repository text (docs, comments, docstrings, commit messages,
  PR bodies) is written in Japanese, with enough context for an engineer new
  to the repository.
- Agent-facing instruction files (this file, checklists, skills) are written
  in concise, LLM-readable English.
