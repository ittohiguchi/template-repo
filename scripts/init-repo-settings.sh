#!/usr/bin/env bash
# scaffold時にGitHub capabilityをpolicyへ確定し、そのpolicyに従って設定を冪等に適用する。
# 通常の再実行では保存済みpolicyを使い、管理条件を変更した場合だけ--refresh-policyで再判定する。
set -euo pipefail

missing_commands=()
for command_name in gh jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    missing_commands+=("${command_name}")
  fi
done
if [ "${#missing_commands[@]}" -gt 0 ]; then
  echo "ERROR: 不足しているコマンド: ${missing_commands[*]}" >&2
  echo "macOS (Homebrew): brew install ${missing_commands[*]}" >&2
  exit 1
fi

CHECKS="pr-fast"
refresh_policy=false
while [ $# -gt 0 ]; do
  case "$1" in
    --checks)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "ERROR: --checksにはcheck名が必要です" >&2
        exit 1
      fi
      CHECKS="$2"
      shift 2
      ;;
    --refresh-policy)
      refresh_policy=true
      shift
      ;;
    *)
      echo "不明な引数: $1" >&2
      exit 1
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel)"
policy_file="${REPOSITORY_POLICY_FILE:-${repo_root}/.github/repository-policy.json}"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

ruleset_http=""
ruleset_error=""
policy_tmp=""
cleanup() {
  [ -z "${ruleset_http}" ] || rm -f "${ruleset_http}"
  [ -z "${ruleset_error}" ] || rm -f "${ruleset_error}"
  [ -z "${policy_tmp}" ] || rm -f "${policy_tmp}"
}
trap cleanup EXIT

generate_policy() {
  local repo_json owner owner_type visibility account_json plan
  local ruleset ruleset_reason enforcement http_code response_json message
  local checks_json

  if ! repo_json="$(gh api "repos/${REPO}")"; then
    echo "ERROR: repository情報を取得できませんでした" >&2
    return 1
  fi
  if ! jq -e '.permissions.admin == true' <<<"${repo_json}" >/dev/null; then
    echo "ERROR: repository policyの確定にはadmin権限が必要です" >&2
    return 1
  fi

  owner="$(jq -er '.owner.login' <<<"${repo_json}")"
  owner_type="$(jq -er '.owner.type | ascii_downcase' <<<"${repo_json}")"
  visibility="$(jq -er '.visibility' <<<"${repo_json}")"

  case "${owner_type}" in
    organization)
      if ! account_json="$(gh api "orgs/${owner}")"; then
        echo "ERROR: organization planを取得できませんでした" >&2
        return 1
      fi
      plan="$(jq -er '.plan.name' <<<"${account_json}")"
      ;;
    user)
      if ! account_json="$(gh api user)"; then
        echo "ERROR: account planを取得できませんでした" >&2
        return 1
      fi
      if [ "$(jq -r '.login // empty' <<<"${account_json}")" = "${owner}" ]; then
        plan="$(jq -er '.plan.name' <<<"${account_json}")"
      else
        plan="unknown"
      fi
      ;;
    *)
      echo "ERROR: 未対応のowner種別です: ${owner_type}" >&2
      return 1
      ;;
  esac

  ruleset_http="$(mktemp)"
  ruleset_error="$(mktemp)"
  if gh api "repos/${REPO}/rulesets" --include >"${ruleset_http}" 2>"${ruleset_error}"; then
    ruleset="available"
    ruleset_reason=""
    enforcement="enforced"
  else
    http_code="$(awk '/^HTTP/{code=$2} END{print code}' "${ruleset_http}")"
    response_json="$(sed -n '/^[[:space:]]*{/,$p' "${ruleset_http}")"
    message="$(jq -r '.message // empty' <<<"${response_json}" 2>/dev/null || true)"

    # Business: GitHub Freeのprivate repositoryだけは強制機能なしでscaffoldを完了できる。
    # 403一般を許容すると認証・権限障害をplan制約として隠すため、観測条件をすべて照合する。
    if [ "${visibility}" = "private" ] && \
      [ "${plan}" = "free" ] && \
      [ "${http_code}" = "403" ] && \
      [[ "${message}" == *"make this repository public to enable this feature"* ]]; then
      ruleset="unavailable"
      ruleset_reason="plan"
      enforcement="advisory"
    else
      echo "ERROR: ruleset capabilityを判定できませんでした" >&2
      [ -z "${message}" ] || echo "GitHub API: ${message} (HTTP ${http_code:-unknown})" >&2
      cat "${ruleset_error}" >&2
      return 1
    fi
  fi

  checks_json="$(printf '%s\n' "${CHECKS}" | tr ',' '\n' | jq -R 'select(length > 0)' | jq -s .)"
  if [ "$(jq 'length' <<<"${checks_json}")" -eq 0 ]; then
    echo "ERROR: required checkを1件以上指定してください" >&2
    return 1
  fi

  mkdir -p "$(dirname "${policy_file}")"
  policy_tmp="$(mktemp "${policy_file}.tmp.XXXXXX")"
  jq -n \
    --arg repository "${REPO}" \
    --arg owner_type "${owner_type}" \
    --arg plan "${plan}" \
    --arg visibility "${visibility}" \
    --arg ruleset "${ruleset}" \
    --arg ruleset_reason "${ruleset_reason}" \
    --arg enforcement "${enforcement}" \
    --argjson checks "${checks_json}" \
    '{
      schema_version: 1,
      github: {
        repository: $repository,
        owner_type: $owner_type,
        plan: $plan,
        visibility: $visibility,
        ruleset: $ruleset,
        ruleset_reason: (if $ruleset_reason == "" then null else $ruleset_reason end)
      },
      pull_requests: {
        checks: $checks,
        enforcement: $enforcement
      },
      release: {
        required_statuses: ["release/main-verification", "release/secret-scan"]
      }
    }' >"${policy_tmp}"
  mv "${policy_tmp}" "${policy_file}"
  policy_tmp=""
  echo "repository policyを保存しました: ${policy_file}"
}

validate_policy() {
  jq -e --arg repository "${REPO}" '
    .schema_version == 1 and
    .github.repository == $repository and
    (.github.owner_type == "organization" or .github.owner_type == "user") and
    (.github.plan | type == "string" and length > 0) and
    (.github.visibility == "public" or .github.visibility == "private" or .github.visibility == "internal") and
    (
      (.github.ruleset == "available" and .github.ruleset_reason == null and .pull_requests.enforcement == "enforced") or
      (.github.ruleset == "unavailable" and (.github.ruleset_reason | type == "string" and length > 0) and .pull_requests.enforcement == "advisory")
    ) and
    (.pull_requests.checks | type == "array" and length > 0 and all(type == "string" and length > 0)) and
    (.release.required_statuses | type == "array" and length > 0 and all(type == "string" and length > 0))
  ' "${policy_file}" >/dev/null
}

if [ ! -f "${policy_file}" ] || [ "${refresh_policy}" = "true" ]; then
  generate_policy
else
  echo "保存済みrepository policyを適用します: ${policy_file}"
fi

if ! validate_policy; then
  echo "ERROR: repository policyが不正か、対象repositoryと一致しません: ${policy_file}" >&2
  exit 1
fi

visibility="$(jq -r '.github.visibility' "${policy_file}")"
enforcement="$(jq -r '.pull_requests.enforcement' "${policy_file}")"
checks_json="$(jq -c '[.pull_requests.checks[] | {context: .}]' "${policy_file}")"
checks_display="$(jq -r '.pull_requests.checks | join(",")' "${policy_file}")"

# enforced policyでは全設定変更より先にAPIを再確認し、部分適用を防ぐ。
rulesets_json='[]'
if [ "${enforcement}" = "enforced" ]; then
  if ! rulesets_json="$(gh api "repos/${REPO}/rulesets")"; then
    echo "ERROR: enforced policyのruleset API preflightに失敗したため設定変更を行いません" >&2
    exit 1
  fi
fi

echo "==> ${REPO} に設定を適用します (PR checks: ${checks_display})"

gh api -X PATCH "repos/${REPO}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_auto_merge=true \
  -F allow_update_branch=true \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY >/dev/null
echo "OK: merge 設定 (squash のみ / auto-merge / ブランチ更新・自動削除)"

if [ "${visibility}" = "public" ]; then
  SECURITY_STATUS="enabled"
  SECURITY_SCOPE="public"
  SECURITY_DISPLAY="有効"
else
  SECURITY_STATUS="disabled"
  SECURITY_SCOPE="${visibility}"
  SECURITY_DISPLAY="無効"
fi

security_json="$(jq -n --arg security_status "${SECURITY_STATUS}" '{
  security_and_analysis: {
    secret_scanning: {status: $security_status},
    secret_scanning_push_protection: {status: $security_status}
  }
}')"
echo "${security_json}" | gh api -X PATCH "repos/${REPO}" --input - >/dev/null

actual_security_status="$(
  gh api "repos/${REPO}" \
    --jq '[.security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | join(",")'
)"
expected_security_status="${SECURITY_STATUS},${SECURITY_STATUS}"
if [ "${actual_security_status}" != "${expected_security_status}" ]; then
  echo "ERROR: secret scanning 設定の検証に失敗しました (expected: ${expected_security_status}, actual: ${actual_security_status})" >&2
  exit 1
fi
echo "OK: ${SECURITY_SCOPE} repository: secret scanning + push protection ${SECURITY_DISPLAY}"

# Dependabotの自動修正PRはRenovateと競合するため、検知だけをGitHubへ残す。
gh api -X PUT "repos/${REPO}/vulnerability-alerts"
gh api -X DELETE "repos/${REPO}/automated-security-fixes"
echo "OK: Dependabot alerts 有効 / automated security fixes 無効 (修正 PR は Renovate)"

# Renovate AppがPR作成を担うため、workflow tokenはread-onlyを維持する。
if gh api -X PUT "repos/${REPO}/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false; then
  echo "OK: workflow permissions (default read-only)"
else
  echo "ERROR: workflow permissionsを設定できませんでした" >&2
  exit 1
fi

ruleset_json="$(jq -n --argjson checks "${checks_json}" '{
  name: "main-protection",
  target: "branch",
  enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "pull_request", parameters: {
      required_approving_review_count: 0,
      dismiss_stale_reviews_on_push: false,
      require_code_owner_review: false,
      require_last_push_approval: false,
      required_review_thread_resolution: false,
      allowed_merge_methods: ["squash"]
    }},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: false,
      required_status_checks: $checks
    }}
  ]
}')"

if [ "${enforcement}" = "advisory" ]; then
  echo "SKIP: repository policyによりbranch rulesetは利用しません"
else
  existing_id="$(jq -r '[.[] | select(.name == "main-protection")][0].id // empty' <<<"${rulesets_json}")"
  if [ -n "${existing_id}" ]; then
    echo "${ruleset_json}" | gh api -X PUT "repos/${REPO}/rulesets/${existing_id}" --input - >/dev/null
    echo "OK: branch ruleset main-protectionを更新しました (id ${existing_id})"
  else
    echo "${ruleset_json}" | gh api -X POST "repos/${REPO}/rulesets" --input - >/dev/null
    echo "OK: branch ruleset main-protectionを作成しました"
  fi
fi

echo "merge enforcement: ${enforcement}"
echo "==> 完了。${policy_file}をrepositoryへcommitしてください。"
