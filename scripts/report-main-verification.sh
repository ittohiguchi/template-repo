#!/usr/bin/env bash
# mainのproduction検証失敗を1件のIssueへ集約し、必要な検証が回復したら閉じる。
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "使い方: $0 <success|failure> <commit-sha> <run-url> <check-name>" >&2
  exit 1
fi

result="$1"
sha="$2"
run_url="$3"
check_name="$4"
repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
label="main-verification"
title="mainのproduction検証が失敗しています"

if [ "${result}" != "success" ] && [ "${result}" != "failure" ]; then
  echo "resultはsuccessまたはfailureで指定してください" >&2
  exit 1
fi

gh label create "${label}" \
  --repo "${repo}" \
  --color B60205 \
  --description "mainのproduction検証失敗" \
  --force >/dev/null

issue_number=$(gh issue list \
  --repo "${repo}" \
  --state open \
  --label "${label}" \
  --json number \
  --jq '.[0].number // empty')

if [ "${result}" = "failure" ]; then
  body=$(printf '%s\n\n- check: `%s`\n- commit: `%s`\n- run: %s' \
    "production releaseを止めているmain検証の失敗です。" \
    "${check_name}" \
    "${sha}" \
    "${run_url}")
  if [ -n "${issue_number}" ]; then
    gh issue comment "${issue_number}" --repo "${repo}" --body "${body}" >/dev/null
  else
    gh issue create \
      --repo "${repo}" \
      --title "${title}" \
      --label "${label}" \
      --body "${body}" >/dev/null
  fi
  exit 0
fi

if [ -z "${issue_number}" ]; then
  exit 0
fi

required_contexts=${REQUIRED_STATUS_CONTEXTS:-release/main-verification,release/secret-scan}
statuses=$(gh api "repos/${repo}/commits/${sha}/status")
IFS=',' read -r -a contexts <<< "${required_contexts}"
for context in "${contexts[@]}"; do
  state=$(jq -r --arg context "${context}" \
    '[.statuses[] | select(.context == $context)][0].state // "missing"' \
    <<< "${statuses}")
  if [ "${state}" != "success" ]; then
    exit 0
  fi
done

gh issue close "${issue_number}" \
  --repo "${repo}" \
  --comment "必要なproduction検証がcommit ${sha}で回復しました。" >/dev/null
