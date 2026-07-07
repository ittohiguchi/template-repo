#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
check_script="${repo_root}/scripts/check-gitkeep.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

run_case() {
  local name="$1"
  local expected_status="$2"
  shift 2

  local repo="${tmpdir}/${name}"
  mkdir -p "${repo}"
  git -C "${repo}" init --quiet

  (
    cd "${repo}"
    "$@"
    git add .
  )

  set +e
  output="$(cd "${repo}" && "${check_script}" 2>&1)"
  status="$?"
  set -e

  if [[ "${status}" != "${expected_status}" ]]; then
    printf 'case %s: expected status %s, got %s\n%s\n' "${name}" "${expected_status}" "${status}" "${output}" >&2
    return 1
  fi
}

run_case keeps_empty_directory 0 bash -c '
  mkdir -p hoge/fuga
  : > hoge/fuga/.gitkeep
'

run_case rejects_same_directory_file 1 bash -c '
  mkdir -p hoge/fuga
  : > hoge/fuga/.gitkeep
  : > hoge/fuga/piyo.txt
'

run_case rejects_nested_tracked_file 1 bash -c '
  mkdir -p hoge/fuga
  : > hoge/.gitkeep
  : > hoge/fuga/piyo.txt
'

run_case rejects_nested_gitkeep_as_tracked_file 1 bash -c '
  mkdir -p hoge/fuga
  : > hoge/.gitkeep
  : > hoge/fuga/.gitkeep
'
