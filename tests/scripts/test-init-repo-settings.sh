#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
init_script="${repo_root}/scripts/init-repo-settings.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf 'expected output to contain %q\nactual output:\n%s\n' "${needle}" "${haystack}" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    printf 'expected output not to contain %q\nactual output:\n%s\n' "${needle}" "${haystack}" >&2
    return 1
  fi
}

mkdir -p "${tmpdir}/empty-bin"
set +e
missing_output="$(PATH="${tmpdir}/empty-bin" /bin/bash "${init_script}" 2>&1)"
missing_status="$?"
set -e

if [[ "${missing_status}" != "1" ]]; then
  printf 'missing prerequisites: expected status 1, got %s\n%s\n' "${missing_status}" "${missing_output}" >&2
  exit 1
fi
assert_contains "${missing_output}" "不足しているコマンド: gh jq"
assert_contains "${missing_output}" "brew install gh jq"

mock_bin="${tmpdir}/bin"
calls_file="${tmpdir}/gh-calls"
mkdir -p "${mock_bin}"

cat >"${mock_bin}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${GH_CALLS_FILE}"

if [[ "$*" == "repo view --json nameWithOwner -q .nameWithOwner" ]]; then
  printf '%s\n' "example/project"
elif [[ "$*" == "repo view --json isPrivate -q .isPrivate" ]]; then
  printf '%s\n' "${MOCK_IS_PRIVATE}"
elif [[ "$*" == "api repos/example/project --jq "* ]]; then
  printf '%s\n' "${MOCK_SECURITY_STATE}"
elif [[ "$*" == "api repos/example/project/rulesets -q "* ]]; then
  printf '\n'
elif [[ "$*" == *"--input -"* ]]; then
  printf 'stdin=' >>"${GH_CALLS_FILE}"
  cat >>"${GH_CALLS_FILE}"
  printf '\n' >>"${GH_CALLS_FILE}"
fi
MOCK
chmod +x "${mock_bin}/gh"

private_output="$(
  GH_CALLS_FILE="${calls_file}" \
    MOCK_IS_PRIVATE=true \
    MOCK_SECURITY_STATE=disabled,disabled \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" 2>&1
)"
private_calls="$(<"${calls_file}")"

assert_contains "${private_calls}" "allow_squash_merge=true"
assert_contains "${private_calls}" "allow_merge_commit=false"
assert_contains "${private_calls}" "allow_rebase_merge=false"
assert_contains "${private_calls}" "allow_auto_merge=true"
assert_contains "${private_calls}" "allow_update_branch=true"
assert_contains "${private_calls}" "delete_branch_on_merge=true"
assert_contains "${private_calls}" "squash_merge_commit_title=PR_TITLE"
assert_contains "${private_calls}" "squash_merge_commit_message=PR_BODY"
assert_contains "${private_calls}" '"secret_scanning"'
assert_contains "${private_calls}" '"secret_scanning_push_protection"'
assert_contains "${private_calls}" '"status": "disabled"'
assert_not_contains "${private_calls}" '"status": "enabled"'
assert_contains "${private_output}" "private repository: secret scanning + push protection 無効"
assert_contains "${private_output}" "squash のみ / auto-merge / ブランチ更新・自動削除"
assert_contains "${private_calls}" '"context": "pr-fast"'

: >"${calls_file}"
public_output="$(
  GH_CALLS_FILE="${calls_file}" \
    MOCK_IS_PRIVATE=false \
    MOCK_SECURITY_STATE=enabled,enabled \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" 2>&1
)"
public_calls="$(<"${calls_file}")"

assert_contains "${public_calls}" '"secret_scanning"'
assert_contains "${public_calls}" '"secret_scanning_push_protection"'
assert_contains "${public_calls}" '"status": "enabled"'
assert_contains "${public_output}" "public repository: secret scanning + push protection 有効"

: >"${calls_file}"
set +e
mismatch_output="$(
  GH_CALLS_FILE="${calls_file}" \
    MOCK_IS_PRIVATE=true \
    MOCK_SECURITY_STATE=enabled,enabled \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" 2>&1
)"
mismatch_status="$?"
set -e

if [[ "${mismatch_status}" != "1" ]]; then
  printf 'security verification: expected status 1, got %s\n%s\n' \
    "${mismatch_status}" "${mismatch_output}" >&2
  exit 1
fi
assert_contains "${mismatch_output}" "ERROR: secret scanning 設定の検証に失敗"
