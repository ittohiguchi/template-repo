# CI/CD ワークフロー規約

ワークフローファイルは `{prefix}-{what}.yaml` の命名規則に従う。

- **prefix**: 言語・ツール・プラットフォーム(`general`, `python`, `typescript`, `terraform`, `docker` など)
- **what**: 何をするか(`lint`, `typecheck`, `test-unit`, `secret-scan`, `build-push` など)

## 現在のワークフロー

| ファイル | トリガー | 説明 |
|----------|----------|------|
| `general-pr-fast.yaml` | PR | PR差分だけに高速なpre-commit hooksを実行するrequired check |
| `general-main-verification.yaml` | push to main / 手動 | 全検証を実行し、対象SHAへ`release/main-verification`を記録する。失敗は1件のIssueへ集約する |
| `general-secret-scan.yaml` | push to main / 手動 / 週次 | git全履歴をスキャンし、対象SHAへ`release/secret-scan`を記録する |

## プロジェクト固有ワークフローの追加

言語決定後に既存のPR検証とmain検証を拡張する。手順と要件は
`docs/setup-checklist.md`を参照。拡張後は以下を守る:

1. PRでは変更検出により関係する言語の高速taskだけを実行する。全build、全test、integration、e2eは実行しない。
2. mainでは`task check`を実行し、productionに必要な全体整合性を対象SHAへ記録する。
3. PRとmainのjobは、開発者がローカルで使うのと同じ`task` targetを実行する。
4. 連続mergeでは古いmain検証をcancelし、最新SHAを優先する。過去SHAは手動で再検証できるようにする。
5. 言語が増えたらreusable workflowを`{lang}-{what}.yaml`で切り出す。
6. deploy系(`cd-staging.yaml` / `cd-prod.yaml`)の要件は`docs/product-checklist.md`を参照する。
7. このREADMEの表を更新する。

## release認証

`main`は一時的に壊れていてもよい。productionへ進める条件はbranchの現在状態ではなく、対象commit SHAに必要な`release/*` statusが成功していることで表す。

- `release/main-verification`: 全testとproduction buildを含む`task check`
- `release/secret-scan`: git全履歴のsecret scan
- `release/staging`: 同一artifactのstaging deployとsmoke test(product化後)

失敗は`main-verification` labelのIssue 1件へ集約する。新しい失敗は同じIssueへ追記し、必要なstatusが同一SHAで回復した時だけ自動で閉じる。

## 共通ルール

- GitHub Actions は full commit SHA で pin し、version tag をコメントで残す(SHA の更新は Renovate が担う)。
- workflow には最小の `permissions` を明示する(zizmor が検査する)。
