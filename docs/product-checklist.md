# Product Checklist (phase 2)

Agent-facing. Run when the user declares the repository is graduating from
exploration to product. Everything here exists to keep the product cheap to
change: DDD + hexagonal architecture protect the domain, and every rule is
enforced by an executable check, not by prose.

Confirm with the user before starting: deploy target (cloud, runtime),
whether staging and prod environments both exist, and which parts of the
exploration code survive into the product.

## 1. Architecture: DDD + hexagonal

- Restructure the code into hexagonal layers:
  - `domain/models` — pure domain objects. No framework types (no ORM base
    classes, no Pydantic/serialization frameworks, no HTTP types).
  - `domain/ports` — interfaces the domain needs (repositories, external
    services). Interface types only (Protocol / interface / trait).
  - `domain/services` — use cases. Depend on models and ports only.
  - `adapters/incoming` — web handlers, CLI, consumers. Call domain services.
  - `adapters/outgoing` — implementations of ports (DB, external API, LLM).
  - a single composition root (`container` or equivalent) that wires
    adapters into ports.
- Dependencies point inward only: adapters -> domain, never domain -> adapters.
  Incoming and outgoing adapters do not import each other.

## 2. Enforce the architecture with executable contracts

- Enforce import direction with the language's import-contract tool
  (import-linter for Python, dependency-cruiser or eslint boundaries for
  TypeScript, ArchUnit for JVM, go-arch-lint for Go, or equivalent).
  Minimum contracts:
  - layers: adapters above domain (adapters may import domain, not reverse);
  - domain isolation: domain must not import adapters or framework modules;
  - independence: incoming and outgoing adapters independent of each other;
  - domain internal layers: services -> ports -> models.
- Exclude the composition root from the independence contract from the start.
  Do not accumulate per-module ignore entries for it; that list only grows
  (lesson from prd-smaresu-porters, where it reached 40+ lines).
- Enforce naming and idiom rules the import graph cannot see with semgrep
  (or the language's equivalent): ports are interface types, domain models
  are framework-free, suffix conventions such as `*Port` / `*Service` /
  `*Repository` / `*Error`.
- Test the rules themselves: keep fixture files with annotated expected
  findings and a check that fails when a rule stops matching them.
- Wire all of the above into `Taskfile.yml` targets, pre-commit, and `ci.yaml`.

## 3. Environment model

- Use exactly three environment words: `local`, `staging`, `prod`.
  `local` covers laptops, CI, emulators, and every kind of test. Never call
  a shared cloud environment "dev".
- Treat `staging` and `prod` data boundaries, PII constraints, and permission
  requirements as equivalent.
- Manage all `staging` / `prod` cloud resources, deploy identities, and
  permissions with IaC. Authenticate CI/CD via OIDC (e.g. Workload Identity
  Federation), not long-lived keys. If an emergency requires a manual change,
  reflect it back into IaC in the same or the immediately following change set.

## 4. Deploys: consolidated in GitHub Actions

- All deploys run from GitHub Actions. No deploys from developer machines.
- `cd-staging.yaml`: auto-deploys `main` on push, path-filtered to build
  inputs (source, lockfiles, Dockerfile) so docs/test-only changes do not
  redeploy.
- `cd-prod.yaml`: triggered only by pushing an annotated tag matching
  `prod-YYYY.MM.DD-NN`. `workflow_dispatch` exists only as an emergency
  fallback and requires an explicit `git_ref`.
- Use GitHub Environments `staging` and `prod` for scoped credentials and
  (for prod) required reviewers if desired.
- Promote the same artifact: derive image/bundle tags from content hashes so
  the artifact validated on staging is byte-identical to what prod runs.

## 5. Release rule

- Production releases are immutable annotated tags `prod-YYYY.MM.DD-NN`
  (`NN` = zero-padded sequence within the calendar day, Asia/Tokyo).
- Tag only commits that are reachable from `origin/main` and already
  validated on staging.
- Never move, delete, or recreate a prod tag. Retries and rollbacks cut a
  new tag pointing at the appropriate commit.
- Create a `prod-tag-release` skill under `.claude/skills/` with a helper
  script that picks the next tag number and fails if the target commit is
  not on `origin/main`. The release procedure must be runnable by an agent
  without improvisation.

## 6. Guardrails for audits and reviews

Add a section with these rules to `CLAUDE.md` when the product phase starts:

- Do not widen the scope of a constraint beyond its written conditions.
- Keep `local` / `staging` / `prod` and dev-credential / prod-credential
  distinctions intact when reasoning about vulnerabilities; verify a finding
  is on a real production code path before treating it as one.
- Distinguish immediately exploitable issues from hardening improvements.
- Before filing a security issue, confirm reachability, the environment where
  it applies, and the exact rule text it violates.

## 7. Data handling (if the product touches user data)

- Write `docs/policies/data-handling.md` in Japanese covering: what data is
  PII, retention limits and deletion mechanisms, what must never be written
  to logs/traces/metrics, and multi-tenant boundaries if applicable
  (credentials of tenant A must never read or write tenant B data, across
  every path: persistence, caches, queues, LLM preprocessing, temp files).
- Link it from `CLAUDE.md` and keep `CLAUDE.md` itself thin.
