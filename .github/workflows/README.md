# CI/CD ワークフロー規約

ワークフローファイルは `{prefix}-{what}.yaml` の命名規則に従う。

- **prefix**: 言語・ツール・プラットフォーム(`general`, `python`, `typescript`, `terraform`, `docker` など)
- **what**: 何をするか(`lint`, `typecheck`, `test-unit`, `secret-scan`, `build-push` など)

## 現在のワークフロー

| ファイル | トリガー | 説明 |
|----------|----------|------|
| `general-pre-commit.yaml` | PR / push to main | pre-commit hooks を全ファイルに実行(ローカルと同一の検証) |
| `general-secret-scan.yaml` | PR / push to main / 週次 | gitleaks CLI で git 全履歴をスキャン(バージョンの正本は `.pre-commit-config.yaml` の rev) |

## プロジェクト固有ワークフローの追加

言語決定後に `ci.yaml`(オーケストレーター)を作成する。手順と要件は
`docs/setup-checklist.md` を参照。作成後は以下を守る:

1. 変更検出で関係する言語の job だけを起動し、重い suite は入力パスが変わったときだけ走らせる。
2. job は開発者がローカルで使うのと同じ `task` target を実行する。
3. 言語が増えたら reusable workflow を `{lang}-{what}.yaml` で切り出し、`ci.yaml` から呼ぶ。
4. deploy 系(`cd-staging.yaml` / `cd-prod.yaml`)の要件は `docs/product-checklist.md` を参照。
5. この README の表を更新する。

## 共通ルール

- GitHub Actions は full commit SHA で pin し、version tag をコメントで残す(SHA の更新は Renovate が担う)。
- workflow には最小の `permissions` を明示する(zizmor が検査する)。
