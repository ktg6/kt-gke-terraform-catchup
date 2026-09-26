# 学習課題

上から順に。各項目は1回の学習セッション (数時間) 程度。

## 1. Terraform

- `terraform plan` の出力を読み、作成されるリソースと依存関係を把握
- `terraform state list` / `terraform state show` で state の中身を確認
- `node_count` を変数で 3 に → plan で差分 (in-place 更新か再作成か) を確認
- 既存リソースを GUI で変更 → plan でドリフト検出
- 自作 module 化: `envs/dev` の VPC 部分を `modules/network` に切り出す

## 1-2. GKE アップグレード (任意)

1. `gcloud container get-server-config --location=us-central1-a` で REGULAR チャネルの旧バージョンを確認 (Istio 1.30 の対応 Kubernetes バージョンも確認)
2. `gke_version` (旧バージョン) と `upgrade_exclusion_start` / `_end` (UTC RFC3339, 最大 90 日。両方指定必須) を指定して apply → 自動更新を停止した状態で作成
   - `gke_version` は下限指定のため、作成後に `terraform output control_plane_version` / `node_pool_version` で実バージョンを確認。不一致なら plan/apply 時に check 警告が出る
   - CI の場合は GitHub Variables `GKE_VERSION` / `GKE_UPGRADE_EXCLUSION_START` / `GKE_UPGRADE_EXCLUSION_END`
3. コントロールプレーン → spot ノードプールの順に 1 minor ずつ手動更新 (`gcloud container clusters upgrade`)
4. 各段階で `terraform output` の実バージョン、アプリ・DB の状態を確認。ノードは 1 台ずつ入れ替わる (`max_surge=0`, `max_unavailable=1`)
5. 手動更新後は `gke_version` を更新するか空にし、Terraform と実態を揃える

## 2. Kubernetes / Helm

- `helm template t charts/todo` で生成される YAML を確認
- `kubectl describe` / `logs` / `events` でデプロイ過程を追う
- Pod を削除 → Deployment が再作成するのを確認
- 課題: HPA (HorizontalPodAutoscaler) を chart に追加

## 3. ArgoCD

- UI で app-of-apps のツリーと sync-wave の順序を確認
- `kubectl edit` でリソースを手動変更 → selfHeal で戻ることを確認
- `values.yaml` の変更を push → 自動同期を確認
- ロールバック: 過去コミットの revert → 同期

## 4. Istio / Envoy / Gateway API

- `kubectl -n todo get pods` で sidecar (`istio-proxy`) を確認 (2/2)
- **カナリア**: `values.yaml` で `canary.enabled: true`, `canary.tag: <別のSHA>` → `curl localhost:8080/` を繰り返し比率確認。`-H 'x-canary: true'` で canary 固定
- **mTLS**: sidecar なし Pod から `curl todo-stable.todo` → STRICT により拒否されることを確認
- **Envoy 設定確認**: `istioctl proxy-config routes deploy/todo-stable -n todo`
- **リトライ・タイムアウト**: HTTPRoute に `timeouts` を追加
- **外部 LB**: Gateway の annotation を `LoadBalancer` に → 外部 IP でアクセス → 必ず戻す

## 5. CI/CD

- `apps/todo` を変更して PR → test のみ実行されることを確認
- main マージ → build/push → values 更新コミット → ArgoCD 同期までを追う
- Terraform: PR で fmt/validate、workflow_dispatch で plan/apply

## 6. Datadog

- Infrastructure → Kubernetes でノード・Pod のメトリクス確認
- モニター (アラート) を1つ作成: 例 Pod の再起動回数
- トライアル中に試す: `logs.enabled: true` でログ収集、APM
- トライアル終了後: Free プランの範囲 (メトリクス 1 日保持) を確認

## 7. kagent

- UI から k8s-agent に「todo namespace の Pod の状態を教えて」
- わざと壊す (存在しないイメージタグにする等) → 原因調査をエージェントに依頼
- istio-agent に mTLS 設定の説明を依頼
- 課題: 独自の Agent リソースを YAML で定義
