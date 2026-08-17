#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
init_script="${repo_root}/scripts/init-repo-settings.sh"

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

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

mkdir -p "${test_root}/empty-bin"
set +e
missing_output="$(PATH="${test_root}/empty-bin" /bin/bash "${init_script}" 2>&1)"
missing_exit_code="$?"
set -e

if [[ "${missing_exit_code}" != "1" ]]; then
  printf 'missing prerequisites: expected exit code 1, got %s\n%s\n' \
    "${missing_exit_code}" "${missing_output}" >&2
  exit 1
fi
assert_contains "${missing_output}" "不足しているコマンド: gh jq"

mock_bin="${test_root}/bin"
calls_file="${test_root}/gh-calls"
mkdir -p "${mock_bin}"

cat >"${mock_bin}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${MOCK_CALLS_FILE}"

if [[ "$*" == "repo view --json nameWithOwner -q .nameWithOwner" ]]; then
  printf '%s\n' "example/project"
elif [[ "$*" == "api repos/example/project" ]]; then
  if [[ "${MOCK_PROBE_FAILURE:-}" == "repository" ]]; then
    printf '%s\n' "network unavailable" >&2
    exit 1
  fi
  jq -n \
    --arg owner_type "${MOCK_OWNER_TYPE:-Organization}" \
    --arg visibility "${MOCK_VISIBILITY:-private}" \
    --argjson admin "${MOCK_ADMIN:-true}" \
    '{owner:{login:"example",type:$owner_type},visibility:$visibility,permissions:{admin:$admin}}'
elif [[ "$*" == "api orgs/example" || "$*" == "api user" ]]; then
  if [[ "${MOCK_PROBE_FAILURE:-}" == "plan" ]]; then
    printf '%s\n' "authentication failed" >&2
    exit 1
  fi
  jq -n --arg plan "${MOCK_PLAN:-free}" '{login:"example",plan:{name:$plan}}'
elif [[ "$*" == "api repos/example/project/rulesets --include" ]]; then
  case "${MOCK_RULESET_RESULT:-entitlement}" in
    available)
      printf 'HTTP/2.0 200 OK\n\n[]\n'
      ;;
    entitlement)
      printf 'HTTP/2.0 403 Forbidden\n\n'
      jq -n '{message:"Upgrade to GitHub Pro or make this repository public to enable this feature.",status:"403"}'
      exit 1
      ;;
    forbidden)
      printf 'HTTP/2.0 403 Forbidden\n\n'
      jq -n '{message:"Resource not accessible by personal access token",status:"403"}'
      exit 1
      ;;
    network)
      printf '%s\n' "network unavailable" >&2
      exit 1
      ;;
  esac
elif [[ "$*" == "api repos/example/project/rulesets" ]]; then
  if [[ "${MOCK_RULESET_RESULT:-available}" == "available" ]]; then
    jq -n --arg existing_id "${MOCK_EXISTING_RULESET_ID:-}" \
      'if $existing_id == "" then [] else [{name:"main-protection",id:($existing_id | tonumber)}] end'
  else
    printf '%s\n' "ruleset preflight failed" >&2
    exit 1
  fi
elif [[ "$*" == "api repos/example/project --jq "* ]]; then
  printf '%s\n' "${MOCK_SECURITY_STATE:-disabled,disabled}"
elif [[ "$*" == *"--input -"* ]]; then
  printf 'stdin=' >>"${MOCK_CALLS_FILE}"
  cat >>"${MOCK_CALLS_FILE}"
  printf '\n' >>"${MOCK_CALLS_FILE}"
fi
MOCK
chmod +x "${mock_bin}/gh"

run_init() {
  local policy_file="$1"
  shift
  MOCK_CALLS_FILE="${calls_file}" \
    REPOSITORY_POLICY_FILE="${policy_file}" \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" "$@" 2>&1
}

advisory_policy="${test_root}/advisory-policy.json"
: >"${calls_file}"
advisory_output="$(
  MOCK_PLAN=free \
    MOCK_VISIBILITY=private \
    MOCK_RULESET_RESULT=entitlement \
    run_init "${advisory_policy}"
)"
advisory_calls="$(<"${calls_file}")"

jq -e '
  .schema_version == 1 and
  .github.repository == "example/project" and
  .github.owner_type == "organization" and
  .github.plan == "free" and
  .github.visibility == "private" and
  .github.ruleset == "unavailable" and
  .github.ruleset_reason == "plan" and
  .pull_requests.enforcement == "advisory" and
  .pull_requests.checks == ["pr-fast"]
' "${advisory_policy}" >/dev/null
assert_contains "${advisory_output}" "merge enforcement: advisory"
assert_contains "${advisory_output}" "private repository: secret scanning + push protection 無効"
assert_contains "${advisory_calls}" "api repos/example/project/rulesets --include"
assert_not_contains "${advisory_calls}" "-X POST repos/example/project/rulesets"
assert_not_contains "${advisory_calls}" "-X PUT repos/example/project/rulesets/"

: >"${calls_file}"
reapply_output="$(MOCK_PROBE_FAILURE=repository run_init "${advisory_policy}")"
reapply_calls="$(<"${calls_file}")"
assert_contains "${reapply_output}" "保存済みrepository policyを適用します"
if grep -Fxq "api repos/example/project" "${calls_file}"; then
  echo "保存済みpolicyの適用時にrepository capabilityを再取得しました" >&2
  exit 1
fi
assert_not_contains "${reapply_calls}" "api orgs/example"
assert_not_contains "${reapply_calls}" "api repos/example/project/rulesets --include"

enforced_policy="${test_root}/enforced-policy.json"
: >"${calls_file}"
enforced_output="$(
  MOCK_PLAN=team \
    MOCK_VISIBILITY=public \
    MOCK_RULESET_RESULT=available \
    MOCK_SECURITY_STATE=enabled,enabled \
    run_init "${enforced_policy}"
)"
enforced_calls="$(<"${calls_file}")"
jq -e '
  .github.plan == "team" and
  .github.visibility == "public" and
  .github.ruleset == "available" and
  .github.ruleset_reason == null and
  .pull_requests.enforcement == "enforced"
' "${enforced_policy}" >/dev/null
assert_contains "${enforced_output}" "merge enforcement: enforced"
assert_contains "${enforced_calls}" "-X POST repos/example/project/rulesets"
assert_contains "${enforced_calls}" '"context": "pr-fast"'

: >"${calls_file}"
MOCK_RULESET_RESULT=available \
  MOCK_EXISTING_RULESET_ID=42 \
  MOCK_SECURITY_STATE=enabled,enabled \
  run_init "${enforced_policy}" >/dev/null
enforced_reapply_calls="$(<"${calls_file}")"
assert_contains "${enforced_reapply_calls}" "-X PUT repos/example/project/rulesets/42"
assert_not_contains "${enforced_reapply_calls}" "api orgs/example"

: >"${calls_file}"
set +e
enforced_failure_output="$(MOCK_RULESET_RESULT=network run_init "${enforced_policy}")"
enforced_failure_exit_code="$?"
set -e
if [[ "${enforced_failure_exit_code}" != "1" ]]; then
  printf 'enforced preflight: expected exit code 1, got %s\n' "${enforced_failure_exit_code}" >&2
  exit 1
fi
assert_contains "${enforced_failure_output}" "設定変更を行いません"
enforced_failure_calls="$(<"${calls_file}")"
assert_not_contains "${enforced_failure_calls}" "-X PATCH repos/example/project"

: >"${calls_file}"
MOCK_PLAN=free MOCK_VISIBILITY=private MOCK_RULESET_RESULT=entitlement \
  run_init "${enforced_policy}" --refresh-policy >/dev/null
jq -e '.pull_requests.enforcement == "advisory"' "${enforced_policy}" >/dev/null
refresh_calls="$(<"${calls_file}")"
assert_contains "${refresh_calls}" "api repos/example/project"
assert_contains "${refresh_calls}" "api orgs/example"

for failure in forbidden network; do
  failed_policy="${test_root}/failed-${failure}.json"
  : >"${calls_file}"
  set +e
  failure_output="$(
    MOCK_PLAN=free \
      MOCK_VISIBILITY=private \
      MOCK_RULESET_RESULT="${failure}" \
      run_init "${failed_policy}"
  )"
  failure_exit_code="$?"
  set -e
  if [[ "${failure_exit_code}" != "1" ]]; then
    printf '%s failure: expected exit code 1, got %s\n' "${failure}" "${failure_exit_code}" >&2
    exit 1
  fi
  assert_contains "${failure_output}" "ruleset capabilityを判定できませんでした"
  test ! -e "${failed_policy}"
  failure_calls="$(<"${calls_file}")"
  assert_not_contains "${failure_calls}" "-X PATCH repos/example/project"
  assert_not_contains "${failure_calls}" "-X PUT repos/example/project/"
done

no_admin_policy="${test_root}/no-admin-policy.json"
: >"${calls_file}"
set +e
no_admin_output="$(MOCK_ADMIN=false run_init "${no_admin_policy}")"
no_admin_exit_code="$?"
set -e
if [[ "${no_admin_exit_code}" != "1" ]]; then
  printf 'admin permission: expected exit code 1, got %s\n' "${no_admin_exit_code}" >&2
  exit 1
fi
assert_contains "${no_admin_output}" "admin権限が必要です"
test ! -e "${no_admin_policy}"
no_admin_calls="$(<"${calls_file}")"
assert_not_contains "${no_admin_calls}" "api orgs/example"
assert_not_contains "${no_admin_calls}" "-X PATCH repos/example/project"

personal_policy="${test_root}/personal-policy.json"
: >"${calls_file}"
MOCK_OWNER_TYPE=User MOCK_PLAN=free MOCK_VISIBILITY=private MOCK_RULESET_RESULT=entitlement \
  run_init "${personal_policy}" >/dev/null
jq -e '
  .github.owner_type == "user" and
  .github.plan == "free" and
  .pull_requests.enforcement == "advisory"
' "${personal_policy}" >/dev/null

: >"${calls_file}"
set +e
security_output="$(MOCK_SECURITY_STATE=enabled,enabled run_init "${advisory_policy}")"
security_exit_code="$?"
set -e
if [[ "${security_exit_code}" != "1" ]]; then
  printf 'security verification: expected exit code 1, got %s\n' "${security_exit_code}" >&2
  exit 1
fi
assert_contains "${security_output}" "secret scanning 設定の検証に失敗"
