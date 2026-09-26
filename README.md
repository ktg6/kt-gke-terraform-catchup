# kt-gke-terraform-catchup

GKE × Terraform × GCP × DB 設計・運用のキャッチアップ用最小構成。
**使う時だけ apply、終わったら destroy** で課金を最小化する。

## 構成

```
GitHub Actions ──build/push──▶ Artifact Registry
      │ values.yaml のタグ更新 (GitOps)
      ▼
 GitHub (main) ◀──sync── ArgoCD (app-of-apps)
                             │
GKE ゾーンクラスタ (Spot e2-standard-2 × 2)
 ├─ Istio: Gateway API で入口 → Envoy sidecar 間 mTLS
 ├─ todo (Go) ──▶ PostgreSQL (CloudNativePG, primary + replica)
 ├─ Datadog Agent          ┐ 任意 (API キー指定時のみ導入)
 └─ kagent (LLM: Gemini)   ┘
```

| ディレクトリ | 内容 |
|---|---|
| `terraform/bootstrap` | 永続リソース: state バケット, WIF, SA, Artifact Registry, 予算アラート (手動 apply 1回) |
| `terraform/envs/dev` | VPC + GKE (都度 apply / destroy。CI からも実行可) |
| `apps/todo` | Go 製 Todo API。解説: [docs/go.md](docs/go.md) |
| `charts/todo` | 自作 Helm chart (Deployment / HTTPRoute / マイグレーション Job / mTLS) |
| `gitops/apps` | app-of-apps で管理する必須構成 (Istio, CNPG, Gateway, todo) |
| `gitops/optional` | 任意構成 (Datadog, kagent)。API キー指定時に bootstrap.sh が登録 |
| `scripts/` | `bootstrap.sh` (ArgoCD 導入) / `teardown.sh` (destroy 前の後始末) |

## 費用の目安 (us-central1)

**無料構成ではない。** GKE 無料枠はクラスタ管理手数料のみに充当され、ノード (VM)・ディスクは課金される。

- GKE 管理手数料: ゾーンクラスタ1つは無料枠で $0
- ノード (Spot e2-standard-2 × 2): 計 約 $0.04/h (Spot 価格は変動)
- ディスク・外部 IP: 稼働中のみ数セント/日
- LB: 既定は作らない (port-forward でアクセス)。試す時のみ約 $0.025/h
- Artifact Registry / GCS: 無料枠内
- 月 40 時間稼働で数ドル程度。**常時稼働すると月 $30〜50**
- Datadog: Free プラン (5 ホストまで) / kagent: Gemini 無料枠 → $0

予算アラートは通知のみで課金は止まらない。destroy 忘れに注意。

## 可用性の前提 (学習用の割り切り)

本番水準の可用性はない。低コストを優先している。

- ノードは Spot × 2 台・単一ゾーン: 2 台同時回収やゾーン障害で全停止し得る
- DB (primary / replica) は別ノードに分散。片方のノード停止ならフェイルオーバーで継続
- アプリは 2 レプリカ + PDB: drain・ノード更新 (自発的退避) では無停止。Spot 回収 (非自発的) では瞬断あり
- ノード更新は追加ノードなしで 1 台ずつ (`max_surge=0`)。更新中は 1 台分の容量で稼働

## セキュリティ

public リポジトリのため、初回に [docs/security.md](docs/security.md) の GitHub 設定を必ず実施。

## 手順

### 0. 事前準備

- ツール: `gcloud`, `terraform`, `kubectl`, `helm` (v3.14 以上推奨)
- `gcloud auth login && gcloud auth application-default login`
- Datadog: https://www.datadoghq.com/ で登録 (14日トライアル後、自動で Free プランへ)。API キーを控える
  - 登録サイト (US1 / AP1 等) に合わせ `gitops/optional/datadog.yaml` の `site` を修正
- Gemini API キー: https://aistudio.google.com/ で発行 (無料枠。入力は学習に利用され得るため機密を送らない)

### 1. bootstrap (1回のみ)

```sh
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # project_id, billing_account を記入
terraform init && terraform apply
terraform output github_variables               # 次の手順で使用
```

state を GCS へ移す場合: `main.tf` の `backend "gcs"` のコメントを外し
`terraform init -migrate-state -backend-config="bucket=<PROJECT_ID>-tfstate"`。

### 2. GitHub 設定

- Settings → Secrets and variables → Actions → **Variables** に上記 output の6項目を登録 (Secrets 不要)
- アップグレード演習時のみ `GKE_VERSION` / `GKE_UPGRADE_EXCLUSION_START` / `GKE_UPGRADE_EXCLUSION_END` も登録 ([docs/exercises.md](docs/exercises.md))
- [docs/security.md](docs/security.md) の設定

### 3. クラスタ作成

CI: Actions → terraform → Run workflow (`apply`) → Environment の承認。
ローカル:

```sh
cd terraform/envs/dev
terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
terraform apply -var project_id=<PROJECT_ID>
```

### 4. ArgoCD 導入

```sh
$(terraform -chdir=terraform/envs/dev output -raw get_credentials)
./scripts/bootstrap.sh                                   # 必須構成のみ
DD_API_KEY=xxx GOOGLE_API_KEY=xxx ./scripts/bootstrap.sh  # Datadog / kagent も導入 (片方のみも可)
```

ArgoCD は sync-wave 順 (Istio → CNPG → Gateway → DB → アプリ) に、前段が Healthy になるのを待って同期する。

初回はイメージ未 push のため todo は失敗する。`apps/todo` を変更して main に push → CI がイメージ作成・タグ更新 → ArgoCD が自動デプロイ。

### 5. 動作確認

```sh
kubectl -n istio-ingress port-forward svc/gateway-istio 8080:80
curl localhost:8080/
curl -X POST localhost:8080/tasks -d '{"title":"牛乳を買う","tags":["home"]}'
curl localhost:8080/tasks

kubectl -n kagent port-forward svc/kagent-ui 8082:8080   # kagent UI (ポートは kubectl -n kagent get svc で確認)
```

### 6. 後片付け (毎回)

```sh
./scripts/teardown.sh   # PVC ディスクを先に削除 (放置すると課金継続)
```

その後 CI で `destroy`、またはローカルで `terraform destroy`。

## ローカルのみで試す (課金ゼロ)

- アプリ + DB: `cd apps/todo && docker compose up --build`
- k8s 系: kind 等で `./scripts/bootstrap.sh` も実行可 (todo イメージは別途 `kind load` と values 上書きが必要)

## 学習の進め方

[docs/exercises.md](docs/exercises.md) の課題を順に。DB は [docs/db.md](docs/db.md)。
