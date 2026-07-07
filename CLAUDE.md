# Template Repository

GitHub template repository. It ships language-agnostic guardrails only;
language-specific tooling is added when a project is created from it.

## Preinstalled components

- `.pre-commit-config.yaml`: hygiene hooks, gitleaks (secret detection),
  actionlint + zizmor (GitHub Actions lint/security), JSON Schema validation
  for dependabot and workflow files.
- `.github/workflows/pre-commit.yml`: runs all pre-commit hooks on every PR
  and push to main.
- `.github/workflows/secret-scan.yml`: scans the full git history with the
  latest gitleaks release on PRs, pushes to main, and a weekly schedule.
- `.github/workflows/pre-commit-autoupdate.yml`: weekly PR bumping pre-commit
  hook revisions (dependabot does not cover the pre-commit ecosystem).
- `.github/dependabot.yml`: weekly grouped updates for GitHub Actions.
  Language ecosystems are added during setup.
- `.gitleaks.toml`: extends the default gitleaks ruleset; add allowlist
  entries here for false positives.

## Repository conventions

- `CLAUDE.md` is canonical; `AGENTS.md` is a committed symlink to it.
  Keep both present and never replace the symlink with a regular file.
- `.claude/skills/` is canonical; `.agents/skills` is a committed symlink to
  it. Put agent skills under `.claude/skills/`.
- Pin GitHub Actions to a full commit SHA with a version tag comment
  (dependabot keeps the SHAs updated).

## Initial setup checklist (after creating a project from this template)

Work through this once the language/stack is decided.

1. Establish the project commands: lint, format, typecheck, test, build.
2. Create `.github/workflows/ci.yml` that runs those commands on every pull
   request and push to main. Follow the pinning convention above.
3. Add the language package ecosystem(s) to `.github/dependabot.yml`.
4. Add language-specific lint/format hooks to `.pre-commit-config.yaml`.
5. Update `.env.example` with the real variable names (placeholder values only).
6. Run `pre-commit install` locally (install pre-commit via
   `brew install pre-commit` or equivalent).
7. Configure repository settings (GitHub UI or `gh` CLI). Settings are not
   copied from the template, so this is needed for every new repository:
   - Branch ruleset on `main` requiring a pull request and the `pre-commit`,
     `gitleaks`, and `ci` status checks (check contexts are job names).
   - Enable secret scanning and push protection (free for public repos).
   - Allow GitHub Actions to create and approve pull requests
     (Settings > Actions > General); pre-commit-autoupdate.yml fails without
     it. If the toggle is greyed out, enable it at the organization level first.
   - Enable Dependabot alerts and security updates.
8. Rewrite this file for the project: keep "Repository conventions",
   replace the rest with project-specific guidance, and delete this checklist.
