# public リポジトリの安全対策

## 仕組み側で担保済み

- **鍵ファイルなし**: GCP 認証は Workload Identity Federation (短命トークン)。漏えいする長期キーが存在しない
- **WIF の受け入れ条件**: リポジトリ ID (数値) 一致 かつ `main` ブランチのみ。fork・他ブランチ・同名リポジトリからは認証不可
- **Terraform 用 SA**: GitHub Environment `gcp` のジョブのみ使用可 → 承認なしで apply/destroy されない
- **最小権限**: Terraform SA は GKE/ネットワーク作成権限のみ。push SA は Artifact Registry の書込のみ
- **PR ワークフロー**: GCP 認証を行わない (fmt/validate/test のみ)。`pull_request_target` は不使用
- **Actions は SHA 固定** + Dependabot で更新
- **外部公開なし**: Gateway は ClusterIP、ArgoCD / kagent UI も port-forward のみ
- **Secret は Git に置かない**: API キーは `bootstrap.sh` 実行時に環境変数から直接作成
- **予算アラート**: 想定外の課金を検知

## GitHub で手動設定する項目

Settings → Actions → General
- Fork pull request workflows: **Require approval for all external contributors**
- Workflow permissions: **Read repository contents and packages permissions**
- **Allow GitHub Actions to create and approve pull requests** のチェックを外す

Settings → Environments → New environment `gcp`
- **Required reviewers**: 自分
- **Deployment branches**: Selected branches → `main`

Settings → Rules → Rulesets (対象: `main`)
- **Restrict deletions** / **Block force pushes** を有効
- (PR 必須にすると CI のタグ更新 push が失敗するため今回は付けない)

Settings → Code security
- **Secret scanning** と **Push protection** を有効 (public は無料)
- **Dependabot alerts** を有効

アカウント
- GitHub / Google アカウントの 2 段階認証を有効化

## やってはいけないこと

- `terraform.tfvars`・`*.tfstate`・API キーのコミット (`.gitignore` 済みだが `git status` で確認)
- Gateway を LoadBalancer にしたまま放置 (認証なし API が公開状態になる)
- `pull_request_target` や `workflow_run` で fork のコードを実行
