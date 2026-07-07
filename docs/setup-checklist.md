# Setup Checklist (phase 1)

Agent-facing. Run once, right after creating a repository from this template
and deciding the language/stack. Report each item's result to the user.

## Preinstalled guardrails (do not recreate)

- `.pre-commit-config.yaml`: hygiene hooks, gitleaks (secret detection),
  actionlint + zizmor (GitHub Actions lint/security), JSON Schema validation
  for dependabot and workflow files.
- `.github/workflows/general-pre-commit.yaml`: runs all pre-commit hooks on
  every PR and push to main.
- `.github/workflows/general-secret-scan.yaml`: scans the full git history
  with the latest gitleaks release on PRs, pushes to main, and weekly.
- `.github/workflows/general-pre-commit-autoupdate.yaml`: weekly PR bumping
  pre-commit hook revisions (dependabot does not cover pre-commit).
- `.github/dependabot.yml`: weekly grouped updates for GitHub Actions.
- `.gitleaks.toml`: extends the default gitleaks ruleset; add allowlist
  entries there for false positives.
- `Taskfile.yml`: single entry point for dev commands.

## Checklist

1. Establish the project commands: lint, format, typecheck, test, build.
   Add each as a task in `Taskfile.yml` with a `desc:` so `task --list`
   stays the complete command catalog.
2. Create the CI orchestrator `.github/workflows/ci.yaml`:
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
3. Add the language package ecosystem(s) to `.github/dependabot.yml`.
4. Add language-specific lint/format hooks to `.pre-commit-config.yaml`.
5. Update `.env.example` with the real variable names (placeholder values
   only; never real values).
6. Run `task setup` locally (installs the pre-commit git hook). Prerequisites:
   `brew install pre-commit go-task` or equivalent.
7. Configure repository settings (GitHub UI or `gh` CLI). Settings are not
   copied from the template, so this is needed for every new repository:
   - Branch ruleset on `main` requiring a pull request and the `pre-commit`,
     `gitleaks`, and `ci` status checks (check contexts are job names).
   - Enable secret scanning and push protection (free for public repos).
   - Allow GitHub Actions to create and approve pull requests
     (Settings > Actions > General); general-pre-commit-autoupdate.yaml fails
     without it. If the toggle is greyed out, enable it at the organization
     level first.
   - Enable Dependabot alerts and security updates.
8. Replace the description at the top of `CLAUDE.md` with a one-paragraph
   project description. Keep every other section; the repository is now in
   the exploration phase of the phase model.
