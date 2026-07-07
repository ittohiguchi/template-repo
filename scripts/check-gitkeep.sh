#!/usr/bin/env bash
set -euo pipefail

if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  echo "Git リポジトリ内で実行してください。" >&2
  exit 2
fi

failed=0

while IFS= read -r -d '' keep; do
  [[ "$(basename "${keep}")" == ".gitkeep" ]] || continue

  dir="$(dirname "${keep}")"

  while IFS= read -r -d '' tracked; do
    if [[ "${tracked}" != "${keep}" ]]; then
      echo "不要な .gitkeep: ${keep}" >&2
      failed=1
      break
    fi
  done < <(git ls-files -z -- "${dir}")
done < <(git ls-files -z)

exit "${failed}"
