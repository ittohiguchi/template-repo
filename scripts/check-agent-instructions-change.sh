#!/usr/bin/env bash
set -euo pipefail

# 対象名への変更・削除・rename・symlink変更を、作業ツリーではなくindexで判定する。
# --all-files等でもstageがなければ通過する。下位directoryからの実行にも対応する。
cd "$(git rev-parse --show-toplevel)"
hook_id=agent-instructions-change
case ",${SKIP:-}," in
  *,"${hook_id}",*) exit 0 ;;
esac
pathspecs=(':(top,glob)**/AGENTS.md' ':(top,glob)**/CLAUDE.md')

if git diff --cached --quiet --no-ext-diff --no-textconv --no-renames -- "${pathspecs[@]}"; then
  exit 0
fi

cat <<EOF
Commit blocked: staged changes to agent instruction files (AGENTS.md / CLAUDE.md).

To agents: unless the user explicitly asked for this change, revert it or show
the user the diff below and get their confirmation. Once confirmed, recommit
skipping only this check:

  SKIP=${hook_id} git commit ...

Do not use --no-verify; it also skips other checks such as secret scanning.

EOF
git --no-pager diff --cached --no-color --no-ext-diff --no-textconv --no-renames -- "${pathspecs[@]}"
exit 1
