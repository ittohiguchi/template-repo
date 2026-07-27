#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
init_script="${repo_root}/scripts/init-org-settings.sh"

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
    printf 'expected output not to contain %q\nactual output:\n%s\n' \
      "${needle}" "${haystack}" >&2
    return 1
  fi
}

assert_call_count() {
  local calls="$1"
  local needle="$2"
  local expected="$3"
  local actual

  actual="$(grep -c -- "${needle}" <<<"${calls}" || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected %q call count %s, got %s\ncalls:\n%s\n' \
      "${needle}" "${expected}" "${actual}" "${calls}" >&2
    return 1
  fi
}

mkdir -p "${tmpdir}/empty-bin"
set +e
missing_output="$(PATH="${tmpdir}/empty-bin" /bin/bash "${init_script}" example 2>&1)"
missing_status="$?"
set -e

if [[ "${missing_status}" != "1" ]]; then
  printf 'missing prerequisites: expected status 1, got %s\n%s\n' \
    "${missing_status}" "${missing_output}" >&2
  exit 1
fi
assert_contains "${missing_output}" "不足しているコマンド: gh jq"

mock_bin="${tmpdir}/bin"
calls_file="${tmpdir}/gh-calls"
budget_reads_file="${tmpdir}/budget-reads"
mkdir -p "${mock_bin}"

cat >"${mock_bin}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${GH_CALLS_FILE}"

if [[ "$*" == *"settings/billing/budgets?per_page=100"* ]]; then
  read_count=0
  if [[ -f "${BUDGET_READS_FILE}" ]]; then
    read_count="$(<"${BUDGET_READS_FILE}")"
  fi
  read_count="$((read_count + 1))"
  printf '%s' "${read_count}" >"${BUDGET_READS_FILE}"
  if [[ "${read_count}" == "1" ]]; then
    printf '%s\n' "${MOCK_INITIAL_BUDGETS}"
  else
    printf '%s\n' "${MOCK_FINAL_BUDGETS}"
  fi
elif [[ "$*" == *"api orgs/example/code-security/configurations"* ]] &&
  [[ "$*" != *"/defaults"* ]] && [[ "$*" != *"/attach"* ]] &&
  [[ "$*" != *"/${MOCK_SECURITY_CONFIGURATION_ID}"* ]] &&
  [[ "$*" != *"-X POST"* ]]; then
  printf '%s\n' "${MOCK_SECURITY_CONFIGURATIONS}"
elif [[ "$*" == *"api orgs/example/code-security/configurations/defaults"* ]]; then
  printf '[{"default_for_new_repos":"private_and_internal","configuration":{"id":%s}}]\n' \
    "${MOCK_SECURITY_CONFIGURATION_ID}"
elif [[ "$*" == *"api -X POST orgs/example/code-security/configurations "* ]]; then
  cat >/dev/null
  printf '{"id":%s}\n' "${MOCK_SECURITY_CONFIGURATION_ID}"
elif [[ "$*" == *"api orgs/example/code-security/configurations/${MOCK_SECURITY_CONFIGURATION_ID}"* ]] &&
  [[ "$*" != *"-X PATCH"* ]] && [[ "$*" != *"/defaults"* ]] && [[ "$*" != *"/attach"* ]]; then
  printf '%s\n' \
    '{"advanced_security":"disabled","dependency_graph":"enabled","dependabot_alerts":"enabled","code_scanning_default_setup":"disabled","secret_scanning":"disabled","secret_scanning_push_protection":"disabled","enforcement":"enforced"}'
elif [[ "$*" == *"api orgs/example/copilot/billing"* ]]; then
  printf '%s\n' '{"seat_breakdown":{"total":0,"pending_invitation":0}}'
elif [[ "$*" == *"--input -"* ]]; then
  printf 'stdin=' >>"${GH_CALLS_FILE}"
  cat >>"${GH_CALLS_FILE}"
  printf '\n' >>"${GH_CALLS_FILE}"
fi
MOCK
chmod +x "${mock_bin}/gh"

initial_budgets='[{"budgets":[
  {"id":"actions-id","budget_type":"ProductPricing","budget_amount":99,"prevent_further_usage":false,"budget_scope":"organization","budget_product_sku":"actions"}
]}]'
final_budgets='[{"budgets":[
  {"id":"actions-id","budget_type":"ProductPricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"actions"},
  {"id":"codespaces-id","budget_type":"ProductPricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"codespaces"},
  {"id":"packages-id","budget_type":"ProductPricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"packages"},
  {"id":"lfs-id","budget_type":"ProductPricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"git_lfs"},
  {"id":"sandbox-id","budget_type":"ProductPricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"sandbox"},
  {"id":"ai-id","budget_type":"BundlePricing","budget_amount":0,"prevent_further_usage":true,"budget_scope":"organization","budget_product_sku":"ai_credits"}
]}]'

success_output="$(
  GH_CALLS_FILE="${calls_file}" \
    BUDGET_READS_FILE="${budget_reads_file}" \
    MOCK_INITIAL_BUDGETS="${initial_budgets}" \
    MOCK_FINAL_BUDGETS="${final_budgets}" \
    MOCK_SECURITY_CONFIGURATIONS='[{"id":123,"name":"Private repositories - paid security disabled"}]' \
    MOCK_SECURITY_CONFIGURATION_ID=123 \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" example 2>&1
)"
calls="$(<"${calls_file}")"
actions_patch="$(
  awk '
    index($0, "-X PATCH organizations/example/settings/billing/budgets/actions-id") {
      capture = 1
    }
    capture && seen && /^api / {
      exit
    }
    capture {
      print
      seen = 1
    }
  ' <<<"${calls}"
)"

assert_call_count "${calls}" "-X PATCH organizations/example/settings/billing/budgets/actions-id" 1
assert_call_count "${calls}" "-X POST organizations/example/settings/billing/budgets" 5
assert_contains "${actions_patch}" '"budget_amount": 0'
assert_contains "${actions_patch}" '"prevent_further_usage": true'
assert_not_contains "${actions_patch}" '"budget_product_sku"'
assert_not_contains "${actions_patch}" '"budget_type"'
assert_contains "${calls}" '"budget_amount": 0'
assert_contains "${calls}" '"prevent_further_usage": true'
assert_contains "${calls}" '"budget_product_sku": "ai_credits"'
assert_contains "${calls}" '"budget_type": "BundlePricing"'
assert_contains "${calls}" "-X PATCH orgs/example/code-security/configurations/123"
assert_contains "${calls}" '"advanced_security": "disabled"'
assert_contains "${calls}" '"secret_scanning": "disabled"'
assert_contains "${calls}" '"secret_scanning_push_protection": "disabled"'
assert_contains "${calls}" '"enforcement": "enforced"'
assert_contains "${calls}" "-X PUT orgs/example/code-security/configurations/123/defaults"
assert_contains "${calls}" '"default_for_new_repos": "private_and_internal"'
assert_contains "${calls}" "-X POST orgs/example/code-security/configurations/123/attach"
assert_contains "${calls}" '"scope": "private_or_internal"'
assert_contains "${calls}" "api orgs/example/code-security/configurations/defaults"
assert_contains "${success_output}" "Actions はプラン内の無料枠まで利用可能"
assert_contains "${success_output}" "Copilot有料seatなし"

: >"${calls_file}"
: >"${budget_reads_file}"
create_output="$(
  GH_CALLS_FILE="${calls_file}" \
    BUDGET_READS_FILE="${budget_reads_file}" \
    MOCK_INITIAL_BUDGETS="${final_budgets}" \
    MOCK_FINAL_BUDGETS="${final_budgets}" \
    MOCK_SECURITY_CONFIGURATIONS='[]' \
    MOCK_SECURITY_CONFIGURATION_ID=456 \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" example 2>&1
)"
create_calls="$(<"${calls_file}")"

assert_contains "${create_calls}" "-X POST orgs/example/code-security/configurations"
assert_contains "${create_calls}" "-X PUT orgs/example/code-security/configurations/456/defaults"
assert_contains "${create_calls}" "-X POST orgs/example/code-security/configurations/456/attach"
assert_contains "${create_output}" "有料Security無効configurationを作成"

: >"${calls_file}"
: >"${budget_reads_file}"
bad_budgets="${final_budgets/\"budget_amount\":0/\"budget_amount\":1}"
set +e
mismatch_output="$(
  GH_CALLS_FILE="${calls_file}" \
    BUDGET_READS_FILE="${budget_reads_file}" \
    MOCK_INITIAL_BUDGETS="${initial_budgets}" \
    MOCK_FINAL_BUDGETS="${bad_budgets}" \
    MOCK_SECURITY_CONFIGURATIONS='[{"id":123,"name":"Private repositories - paid security disabled"}]' \
    MOCK_SECURITY_CONFIGURATION_ID=123 \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" example 2>&1
)"
mismatch_status="$?"
set -e

if [[ "${mismatch_status}" != "1" ]]; then
  printf 'budget verification: expected status 1, got %s\n%s\n' \
    "${mismatch_status}" "${mismatch_output}" >&2
  exit 1
fi
assert_contains "${mismatch_output}" "ERROR: 課金予算の検証に失敗"

: >"${calls_file}"
: >"${budget_reads_file}"
unexpected_budgets="$(
  jq '.[0].budgets += [{
    id: "future-id",
    budget_type: "ProductPricing",
    budget_amount: 10,
    prevent_further_usage: false,
    budget_scope: "organization",
    budget_product_sku: "future_product"
  }]' <<<"${final_budgets}"
)"
set +e
unexpected_output="$(
  GH_CALLS_FILE="${calls_file}" \
    BUDGET_READS_FILE="${budget_reads_file}" \
    MOCK_INITIAL_BUDGETS="${final_budgets}" \
    MOCK_FINAL_BUDGETS="${unexpected_budgets}" \
    MOCK_SECURITY_CONFIGURATIONS='[{"id":123,"name":"Private repositories - paid security disabled"}]' \
    MOCK_SECURITY_CONFIGURATION_ID=123 \
    PATH="${mock_bin}:/opt/homebrew/bin:/bin:/usr/bin" \
    bash "${init_script}" example 2>&1
)"
unexpected_status="$?"
set -e

if [[ "${unexpected_status}" != "1" ]]; then
  printf 'unexpected budget: expected status 1, got %s\n%s\n' \
    "${unexpected_status}" "${unexpected_output}" >&2
  exit 1
fi
assert_contains "${unexpected_output}" "ERROR: 停止されていないorganization予算"
assert_contains "${unexpected_output}" "future_product"
