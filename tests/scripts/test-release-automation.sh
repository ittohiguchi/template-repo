#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

mock_bin="${tmpdir}/bin"
calls_file="${tmpdir}/calls"
mkdir -p "${mock_bin}"

cat > "${mock_bin}/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  fetch)
    exit 0
    ;;
  rev-parse)
    echo "0123456789abcdef0123456789abcdef01234567"
    exit 0
    ;;
  merge-base)
    exit "${MOCK_ANCESTOR_STATUS:-0}"
    ;;
esac
exit 1
MOCK

cat > "${mock_bin}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${MOCK_CALLS_FILE}"
if [ "$1 $2" = "repo view" ]; then
  echo "example/project"
elif [ "$1" = "api" ]; then
  echo "${MOCK_STATUS_JSON}"
elif [ "$1 $2" = "issue list" ]; then
  echo "${MOCK_ISSUE_NUMBER:-}"
fi
MOCK

chmod +x "${mock_bin}/git" "${mock_bin}/gh"

success_statuses='{"statuses":[{"context":"release/main-verification","state":"success"},{"context":"release/secret-scan","state":"success"},{"context":"release/staging","state":"success"}]}'
missing_staging='{"statuses":[{"context":"release/main-verification","state":"success"},{"context":"release/secret-scan","state":"success"}]}'

set +e
success_output=$(
  MOCK_CALLS_FILE="${calls_file}" \
  MOCK_STATUS_JSON="${success_statuses}" \
  PATH="${mock_bin}:${PATH}" \
    "${repo_root}/scripts/check-release-eligibility.sh" HEAD 2>&1
)
success_status="$?"
set -e
if [ "${success_status}" -ne 0 ]; then
  printf '成功条件をrelease可能と判定できませんでした:\n%s\n' "${success_output}" >&2
  exit 1
fi

set +e
missing_output=$(
  MOCK_CALLS_FILE="${calls_file}" \
  MOCK_STATUS_JSON="${missing_staging}" \
  PATH="${mock_bin}:${PATH}" \
    "${repo_root}/scripts/check-release-eligibility.sh" HEAD 2>&1
)
missing_status="$?"
set -e
if [ "${missing_status}" -ne 1 ] || [[ "${missing_output}" != *"release/staging=missing"* ]]; then
  printf 'release認証不足を検出できませんでした:\n%s\n' "${missing_output}" >&2
  exit 1
fi

set +e
ancestor_output=$(
  MOCK_ANCESTOR_STATUS=1 \
  MOCK_CALLS_FILE="${calls_file}" \
  MOCK_STATUS_JSON="${success_statuses}" \
  PATH="${mock_bin}:${PATH}" \
    "${repo_root}/scripts/check-release-eligibility.sh" HEAD 2>&1
)
ancestor_status="$?"
set -e
if [ "${ancestor_status}" -ne 1 ] || [[ "${ancestor_output}" != *"origin/mainから到達できません"* ]]; then
  printf 'main外のcommitを拒否できませんでした:\n%s\n' "${ancestor_output}" >&2
  exit 1
fi

: > "${calls_file}"
MOCK_CALLS_FILE="${calls_file}" \
MOCK_STATUS_JSON="${missing_staging}" \
PATH="${mock_bin}:${PATH}" \
GITHUB_REPOSITORY="example/project" \
  "${repo_root}/scripts/report-main-verification.sh" \
  failure 0123456789abcdef run-url main-verification
grep -Fq "issue create" "${calls_file}"

: > "${calls_file}"
MOCK_CALLS_FILE="${calls_file}" \
MOCK_STATUS_JSON="${missing_staging}" \
MOCK_ISSUE_NUMBER=42 \
PATH="${mock_bin}:${PATH}" \
GITHUB_REPOSITORY="example/project" \
  "${repo_root}/scripts/report-main-verification.sh" \
  failure 0123456789abcdef run-url secret-scan
grep -Fq "issue comment 42" "${calls_file}"
if grep -Fq "issue create" "${calls_file}"; then
  echo "既存Issueがあるのに新しいIssueを作成しました" >&2
  exit 1
fi

: > "${calls_file}"
MOCK_CALLS_FILE="${calls_file}" \
MOCK_STATUS_JSON="${success_statuses}" \
MOCK_ISSUE_NUMBER=42 \
PATH="${mock_bin}:${PATH}" \
GITHUB_REPOSITORY="example/project" \
  "${repo_root}/scripts/report-main-verification.sh" \
  success 0123456789abcdef run-url main-verification
grep -Fq "issue close 42" "${calls_file}"

: > "${calls_file}"
MOCK_CALLS_FILE="${calls_file}" \
MOCK_STATUS_JSON="${missing_staging}" \
MOCK_ISSUE_NUMBER=42 \
REQUIRED_STATUS_CONTEXTS="release/main-verification,release/secret-scan,release/staging" \
PATH="${mock_bin}:${PATH}" \
GITHUB_REPOSITORY="example/project" \
  "${repo_root}/scripts/report-main-verification.sh" \
  success 0123456789abcdef run-url main-verification
if grep -Fq "issue close" "${calls_file}"; then
  echo "必要なstatusが不足しているのにIssueを閉じました" >&2
  exit 1
fi
