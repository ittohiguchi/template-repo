#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="${repo_root}/scripts/check-agent-instructions-change.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
unset SKIP GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

new_repo() {
  mkdir -p "${test_root}/$1"
  cd "${test_root}/$1"
  git -c init.defaultBranch=main init --quiet
  git config user.name 'Guard test'
  git config user.email 'guard-test@example.invalid'
  git config commit.gpgsign false
  git config core.hooksPath .git/hooks
}
expect_status() {
  local expected="$1" actual=0
  shift
  "$@" >"${test_root}/output" 2>&1 || actual=$?
  if [[ "${actual}" != "${expected}" ]]; then
    cat "${test_root}/output" >&2
    printf 'Expected status %s, got %s in %s\n' "${expected}" "${actual}" "$PWD" >&2
    exit 1
  fi
}
blocked() {
  expect_status 1 bash "${guard}"
  grep -Fq 'Commit blocked:' "${test_root}/output"
  grep -Fq 'SKIP=agent-instructions-change git commit' "${test_root}/output"
  grep -Fq 'diff --git' "${test_root}/output"
}
seed() {
  git add .
  git commit --quiet -m seed
}

for file in AGENTS.md CLAUDE.md nested/AGENTS.md 'nested space/CLAUDE.md' $'line\nbreak/AGENTS.md'; do
  new_repo "path-${RANDOM}"
  mkdir -p "$(dirname "${file}")"
  printf 'original\n' >"${file}"
  expect_status 0 bash "${guard}"
  git add .
  blocked
  seed
  expect_status 0 bash "${guard}"
  printf 'unstaged\n' >>"${file}"
  expect_status 0 bash "${guard}"
  git add .
  git show "HEAD:${file}" >"${file}"
  blocked
  git restore --staged --worktree -- .
  git mv "${file}" renamed.md
  blocked
  git reset --hard --quiet HEAD
  git rm --quiet -- "${file}"
  blocked
  SKIP=unrelated,agent-instructions-change expect_status 0 bash "${guard}"
  SKIP=not-agent-instructions-change blocked
  mkdir -p subdir
  (cd subdir && blocked)
done

new_repo rename-in
printf 'original\n' >ordinary.md
seed
git mv ordinary.md AGENTS.md
blocked

new_repo unrelated
mkdir docs
printf 'unrelated\n' >docs/MY-AGENTS.md
printf 'unrelated\n' >CLAUDE.md.bak
git add .
expect_status 0 bash "${guard}"

for path in AGENTS.md nested/AGENTS.md; do
  new_repo "symlink-${RANDOM}"
  mkdir -p "$(dirname "${path}")"
  printf 'original\n' >"$(dirname "${path}")/CLAUDE.md"
  ln -s CLAUDE.md "${path}"
  git add .
  blocked
  seed
  printf 'changed\n' >>"$(dirname "${path}")/CLAUDE.md"
  git add .
  blocked
  git reset --hard --quiet HEAD
  rm "${path}"
  ln -s elsewhere.md "${path}"
  git add .
  blocked
  git reset --hard --quiet HEAD
  rm "${path}"
  printf 'regular file\n' >"${path}"
  git add .
  blocked
  git reset --hard --quiet HEAD
  git rm --quiet -- "${path}"
  blocked
done

new_repo selective-skip
printf 'initial\n' >AGENTS.md
seed
mkdir -p .git/hooks
printf '#!/usr/bin/env bash\nset -e\nbash %q\nprintf checked >.git/other-check-ran\nexit 23\n' "${guard}" >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
printf 'changed\n' >>AGENTS.md
git add AGENTS.md
before="$(git rev-parse HEAD)"
expect_status 1 git commit -m blocked
[[ ! -e .git/other-check-ran ]]
SKIP=agent-instructions-change expect_status 1 git commit -m still-blocked-by-other-check
[[ "$(cat .git/other-check-ran)" == checked ]]
[[ "$(git rev-parse HEAD)" == "${before}" ]]

printf 'Agent instruction guard: all staged-change and selective-skip cases passed.\n'
