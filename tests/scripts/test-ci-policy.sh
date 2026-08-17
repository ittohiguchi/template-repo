#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local file="$1"
  local text="$2"

  if ! grep -Fq -- "${text}" "${repo_root}/${file}"; then
    printf '%s に必要な契約がありません: %s\n' "${file}" "${text}" >&2
    return 1
  fi
}

assert_not_contains() {
  local file="$1"
  local text="$2"

  if grep -Fq -- "${text}" "${repo_root}/${file}"; then
    printf '%s に禁止された契約があります: %s\n' "${file}" "${text}" >&2
    return 1
  fi
}

test -f "${repo_root}/.github/workflows/general-pr-fast.yaml"
test -f "${repo_root}/.github/workflows/general-main-verification.yaml"
test -f "${repo_root}/scripts/report-main-verification.sh"
test -f "${repo_root}/scripts/check-release-eligibility.sh"

assert_contains ".github/workflows/general-pr-fast.yaml" "pull_request:"
assert_contains ".github/workflows/general-pr-fast.yaml" "task check:pr"

assert_contains ".github/workflows/general-main-verification.yaml" "branches: [main]"
assert_contains ".github/workflows/general-main-verification.yaml" "cancel-in-progress: true"
assert_contains ".github/workflows/general-main-verification.yaml" "task check"
assert_contains ".github/workflows/general-main-verification.yaml" "release/main-verification"

assert_not_contains ".github/workflows/general-secret-scan.yaml" "pull_request:"
assert_contains ".github/workflows/general-secret-scan.yaml" "branches: [main]"
assert_contains ".github/workflows/general-secret-scan.yaml" "release/secret-scan"

assert_contains "Taskfile.yml" "check:pr:"
assert_contains "Taskfile.yml" 'pre-commit run --from-ref "$BASE_REF" --to-ref "$HEAD_REF"'
assert_contains "scripts/init-repo-settings.sh" 'CHECKS="pr-fast"'
assert_contains "scripts/init-repo-settings.sh" 'REPOSITORY_POLICY_FILE'
assert_contains "scripts/init-repo-settings.sh" 'ruleset_reason'
assert_contains "docs/setup-checklist.md" '.github/repository-policy.json'
assert_contains "CLAUDE.md" '.github/repository-policy.json'
assert_contains "docs/product-checklist.md" '`release/main-verification`'
assert_contains "docs/product-checklist.md" '`release/staging`'
