#!/usr/bin/env bash
# prod tag作成前に、対象commitがmain上で必要な認証を得ていることを検証する。
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "使い方: $0 <commit-sha> [required-status-context ...]" >&2
  exit 1
fi

target="$1"
shift
if [ "$#" -eq 0 ]; then
  set -- release/main-verification release/secret-scan release/staging
fi

for command_name in git gh jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "不足しているコマンド: ${command_name}" >&2
    exit 1
  fi
done

git fetch origin main >/dev/null
sha=$(git rev-parse --verify "${target}^{commit}")
if ! git merge-base --is-ancestor "${sha}" origin/main; then
  echo "対象commitはorigin/mainから到達できません: ${sha}" >&2
  exit 1
fi

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
statuses=$(gh api "repos/${repo}/commits/${sha}/status")
for context in "$@"; do
  state=$(jq -r --arg context "${context}" \
    '[.statuses[] | select(.context == $context)][0].state // "missing"' \
    <<< "${statuses}")
  if [ "${state}" != "success" ]; then
    echo "release認証が不足しています: ${context}=${state} (${sha})" >&2
    exit 1
  fi
done

echo "release可能: ${sha}"
