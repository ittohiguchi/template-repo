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
elif [[ "$*" == "api repos/example/project/rulesets -q "* ]]; then
  printf '\n'
elif [[ "$*" == *"--input -"* ]]; then
  cat >/dev/null
fi
MOCK
chmod +x "${mock_bin}/gh"

success_output="$(
  GH_CALLS_FILE="${calls_file}" \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" 2>&1
)"
calls="$(<"${calls_file}")"

assert_contains "${calls}" "allow_squash_merge=true"
assert_contains "${calls}" "allow_merge_commit=false"
assert_contains "${calls}" "allow_rebase_merge=false"
assert_contains "${calls}" "allow_auto_merge=true"
assert_contains "${calls}" "allow_update_branch=true"
assert_contains "${calls}" "delete_branch_on_merge=true"
assert_contains "${calls}" "squash_merge_commit_title=PR_TITLE"
assert_contains "${calls}" "squash_merge_commit_message=PR_BODY"
assert_contains "${success_output}" "squash のみ / auto-merge / ブランチ更新・自動削除"
