#!/usr/bin/env bash
# リポジトリ設定を冪等に適用する。repo 作成直後の初期化にも、設定変更の再適用にも使える。
# テンプレートから作った repo にはリポジトリ設定がコピーされないため、必ず一度実行する。
#
# 使い方:
#   scripts/init-repo-settings.sh [--checks pre-commit,gitleaks]
#
# --checks: branch ruleset の required status checks(job 名のカンマ区切り)。
#   ci.yaml を作成したら `--checks pre-commit,gitleaks,ci` で再実行して required に加える。
#   ci が存在しない段階で required にすると PR が永久にブロックされるため、既定には含めない。
set -euo pipefail

CHECKS="pre-commit,gitleaks"
while [ $# -gt 0 ]; do
  case "$1" in
    --checks)
      CHECKS="$2"
      shift 2
      ;;
    *)
      echo "不明な引数: $1" >&2
      exit 1
      ;;
  esac
done

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "==> ${REPO} に設定を適用します (required checks: ${CHECKS})"

# merge 方式は squash のみ(ruleset 側の allowed_merge_methods と揃える)
gh api -X PATCH "repos/${REPO}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true >/dev/null
echo "OK: merge 設定 (squash のみ / merge 後ブランチ自動削除)"

# secret scanning + push protection(public repo は無料。private は GHAS が必要で失敗する)
if gh api -X PATCH "repos/${REPO}" --input - >/dev/null <<'JSON'
{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}
JSON
then
  echo "OK: secret scanning + push protection"
else
  echo "SKIP: secret scanning は有効化できませんでした(private repo では GHAS の課金が必要)" >&2
fi

# 脆弱性の検知は Dependabot alerts に任せる。修正 PR の作成は Renovate
# (vulnerabilityAlerts)が担うため、Dependabot 側の automated security fixes は
# 無効化して二重 PR を防ぐ。
gh api -X PUT "repos/${REPO}/vulnerability-alerts"
gh api -X DELETE "repos/${REPO}/automated-security-fixes"
echo "OK: Dependabot alerts 有効 / automated security fixes 無効 (修正 PR は Renovate)"

# Actions のデフォルトトークンは read-only。PR 作成は Renovate App が行うため
# GITHUB_TOKEN への PR 作成許可 (can_approve_pull_request_reviews) は不要。
if gh api -X PUT "repos/${REPO}/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false; then
  echo "OK: workflow permissions (default read-only)"
else
  echo "ERROR: workflow permissions を設定できませんでした。org 設定が上限の場合は org admin が以下を実行:" >&2
  echo "  gh api -X PUT orgs/<org>/actions/permissions/workflow -f default_workflow_permissions=read" >&2
  exit 1
fi

# branch ruleset を名前で upsert(main への直 push 禁止、PR + required checks 必須、
# force push / 削除禁止)
checks_json=$(echo "$CHECKS" | tr ',' '\n' | jq -R '{context: .}' | jq -s .)
ruleset_json=$(jq -n --argjson checks "$checks_json" '{
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
}')
existing_id=$(gh api "repos/${REPO}/rulesets" -q '[.[] | select(.name == "main-protection")][0].id // empty')
if [ -n "$existing_id" ]; then
  echo "$ruleset_json" | gh api -X PUT "repos/${REPO}/rulesets/${existing_id}" --input - >/dev/null
  echo "OK: branch ruleset main-protection を更新 (id ${existing_id})"
else
  echo "$ruleset_json" | gh api -X POST "repos/${REPO}/rulesets" --input - >/dev/null
  echo "OK: branch ruleset main-protection を作成"
fi

echo "==> 完了。Renovate App が org にインストールされ、この repo をカバーしていることを確認すること:"
echo "    https://github.com/apps/renovate"
