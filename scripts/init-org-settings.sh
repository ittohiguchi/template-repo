#!/usr/bin/env bash
# GitHub organizationの基本プランを維持したまま、追加従量課金を停止する。
#
# 使い方:
#   scripts/init-org-settings.sh <organization>
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

if [ "$#" -ne 1 ] || [[ "$1" == -* ]]; then
  echo "使い方: scripts/init-org-settings.sh <organization>" >&2
  exit 2
fi

ORG="$1"
API_VERSION="2026-03-10"
SECURITY_CONFIGURATION_NAME="Private repositories - paid security disabled"

gh_api() {
  gh api "$@" -H "X-GitHub-Api-Version: ${API_VERSION}"
}

fetch_budgets() {
  gh_api \
    "organizations/${ORG}/settings/billing/budgets?per_page=100" \
    --paginate \
    --slurp |
    jq '[.[].budgets[]]'
}

budget_payload() {
  local budget_type="$1"
  local product_sku="$2"

  jq -n \
    --arg org "${ORG}" \
    --arg budget_type "${budget_type}" \
    --arg product_sku "${product_sku}" \
    '{
      budget_amount: 0,
      prevent_further_usage: true,
      budget_scope: "organization",
      budget_entity_name: $org,
      budget_type: $budget_type,
      budget_product_sku: $product_sku,
      budget_alerting: {
        will_alert: false,
        alert_recipients: []
      }
    }'
}

# Business: Team/Enterpriseの基本料金を除き、追加利用額は常に0円を上限とする。
budget_specs=(
  "ProductPricing:actions"
  "ProductPricing:codespaces"
  "ProductPricing:packages"
  "ProductPricing:git_lfs"
  "ProductPricing:sandbox"
  "BundlePricing:ai_credits"
)

echo "==> ${ORG} の追加従量課金を停止します"
budgets="$(fetch_budgets)"
for budget_spec in "${budget_specs[@]}"; do
  budget_type="${budget_spec%%:*}"
  product_sku="${budget_spec#*:}"
  match_count="$(
    jq \
      --arg budget_type "${budget_type}" \
      --arg product_sku "${product_sku}" \
      '[.[] | select(
        .budget_scope == "organization" and
        .budget_type == $budget_type and
        .budget_product_sku == $product_sku
      )] | length' <<<"${budgets}"
  )"

  if [ "${match_count}" -gt 1 ]; then
    echo "ERROR: ${product_sku} のorganization予算が重複しています" >&2
    exit 1
  fi

  payload="$(budget_payload "${budget_type}" "${product_sku}")"
  if [ "${match_count}" -eq 1 ]; then
    budget_id="$(
      jq -r \
        --arg budget_type "${budget_type}" \
        --arg product_sku "${product_sku}" \
        '.[] | select(
          .budget_scope == "organization" and
          .budget_type == $budget_type and
          .budget_product_sku == $product_sku
        ) | .id' <<<"${budgets}"
    )"
    jq '{
      budget_amount,
      prevent_further_usage
    }' <<<"${payload}" |
      gh_api -X PATCH \
        "organizations/${ORG}/settings/billing/budgets/${budget_id}" \
        --input - >/dev/null
    echo "OK: ${product_sku} の\$0予算を更新"
  else
    echo "${payload}" |
      gh_api -X POST \
        "organizations/${ORG}/settings/billing/budgets" \
        --input - >/dev/null
    echo "OK: ${product_sku} の\$0予算を作成"
  fi
done

budgets="$(fetch_budgets)"
for budget_spec in "${budget_specs[@]}"; do
  budget_type="${budget_spec%%:*}"
  product_sku="${budget_spec#*:}"
  if ! jq -e \
    --arg budget_type "${budget_type}" \
    --arg product_sku "${product_sku}" \
    '[.[] | select(
      .budget_scope == "organization" and
      .budget_type == $budget_type and
      .budget_product_sku == $product_sku and
      .budget_amount == 0 and
      .prevent_further_usage == true
    )] | length == 1' <<<"${budgets}" >/dev/null; then
    echo "ERROR: 課金予算の検証に失敗しました (${product_sku})" >&2
    exit 1
  fi
done

unsafe_budget_names="$(
  jq -r '[
    .[] | select(
      .budget_scope == "organization" and
      (
        .budget_amount != 0 or
        .prevent_further_usage != true
      )
    ) | .budget_product_sku
  ] | unique | join(", ")' <<<"${budgets}"
)"
if [ -n "${unsafe_budget_names}" ]; then
  echo "ERROR: 停止されていないorganization予算: ${unsafe_budget_names}" >&2
  exit 1
fi
echo "OK: 追加従量課金は\$0で停止"

security_payload="$(
  jq -n \
    --arg name "${SECURITY_CONFIGURATION_NAME}" \
    '{
      name: $name,
      description: "private/internal repositoryで有料のAdvanced Security機能を有効化しない。",
      advanced_security: "disabled",
      dependency_graph: "enabled",
      dependency_graph_autosubmit_action: "disabled",
      dependabot_alerts: "enabled",
      dependabot_security_updates: "not_set",
      code_scanning_default_setup: "disabled",
      secret_scanning: "disabled",
      secret_scanning_push_protection: "disabled",
      secret_scanning_non_provider_patterns: "disabled",
      secret_scanning_validity_checks: "disabled",
      enforcement: "enforced"
    }'
)"
security_configurations="$(gh_api "orgs/${ORG}/code-security/configurations")"
security_match_count="$(
  jq \
    --arg name "${SECURITY_CONFIGURATION_NAME}" \
    '[.[] | select(.name == $name)] | length' <<<"${security_configurations}"
)"
if [ "${security_match_count}" -gt 1 ]; then
  echo "ERROR: 同名のcode security configurationが重複しています" >&2
  exit 1
fi

if [ "${security_match_count}" -eq 1 ]; then
  security_configuration_id="$(
    jq -r \
      --arg name "${SECURITY_CONFIGURATION_NAME}" \
      '.[] | select(.name == $name) | .id' <<<"${security_configurations}"
  )"
  echo "${security_payload}" |
    gh_api -X PATCH \
      "orgs/${ORG}/code-security/configurations/${security_configuration_id}" \
      --input - >/dev/null
  echo "OK: 有料Security無効configurationを更新"
else
  security_configuration_id="$(
    echo "${security_payload}" |
      gh_api -X POST "orgs/${ORG}/code-security/configurations" --input - |
      jq -r '.id'
  )"
  if [ -z "${security_configuration_id}" ] ||
    [ "${security_configuration_id}" = "null" ]; then
    echo "ERROR: code security configurationの作成結果にIDがありません" >&2
    exit 1
  fi
  echo "OK: 有料Security無効configurationを作成"
fi

jq -n '{default_for_new_repos: "private_and_internal"}' |
  gh_api -X PUT \
    "orgs/${ORG}/code-security/configurations/${security_configuration_id}/defaults" \
    --input - >/dev/null
jq -n '{scope: "private_or_internal"}' |
  gh_api -X POST \
    "orgs/${ORG}/code-security/configurations/${security_configuration_id}/attach" \
    --input - >/dev/null

actual_security="$(
  gh_api "orgs/${ORG}/code-security/configurations/${security_configuration_id}"
)"
if ! jq -e '
  .advanced_security == "disabled" and
  .dependency_graph == "enabled" and
  .dependabot_alerts == "enabled" and
  .code_scanning_default_setup == "disabled" and
  .secret_scanning == "disabled" and
  .secret_scanning_push_protection == "disabled" and
  .enforcement == "enforced"
' <<<"${actual_security}" >/dev/null; then
  echo "ERROR: code security configurationの検証に失敗しました" >&2
  exit 1
fi

actual_defaults="$(
  gh_api "orgs/${ORG}/code-security/configurations/defaults"
)"
if ! jq -e \
  --argjson configuration_id "${security_configuration_id}" \
  'any(.[];
    .default_for_new_repos == "private_and_internal" and
    .configuration.id == $configuration_id
  )' <<<"${actual_defaults}" >/dev/null; then
  echo "ERROR: private/internal repositoryのdefault設定を検証できませんでした" >&2
  exit 1
fi
echo "OK: private/internal repositoryの有料Securityを強制無効化"

copilot_billing="$(gh_api "orgs/${ORG}/copilot/billing")"
if ! jq -e '
  .seat_breakdown.total == 0 and
  .seat_breakdown.pending_invitation == 0
' <<<"${copilot_billing}" >/dev/null; then
  echo "ERROR: Copilotの有料seatまたは招待が存在します" >&2
  echo "https://github.com/organizations/${ORG}/settings/copilot" >&2
  exit 1
fi
echo "OK: Copilot有料seatなし"

echo "==> 完了。Actions はプラン内の無料枠まで利用可能で、超過時の追加課金は停止します"
