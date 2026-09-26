#!/usr/bin/env bash
# クラスタ作成後に1回実行: ArgoCD 導入 → app-of-apps 登録 → (キー指定時のみ) 任意コンポーネント登録
# 以降のリソースはすべて ArgoCD が Git から同期する
#
#   ./scripts/bootstrap.sh                                  # 必須構成のみ
#   DD_API_KEY=xxx GOOGLE_API_KEY=xxx ./scripts/bootstrap.sh # Datadog / kagent も導入
#   (後から片方だけ追加する場合も同じコマンドを再実行すればよい)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "context: $(kubectl config current-context)"

# Gateway API CRD (GKE は Terraform で有効化済み。kind 等では未導入)
if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version 10.9.2 \
  --namespace argocd --create-namespace --wait \
  -f gitops/argocd-values.yaml

kubectl apply -f gitops/root.yaml

# Secret は Git に置かず、ここで直接作成。キーがあるものだけ Application を登録
add_optional() { # app ns secret key value
  kubectl create namespace "$2" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$2" create secret generic "$3" --from-literal="$4=$5" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "gitops/optional/$1.yaml"
}
if [[ -n "${DD_API_KEY:-}" ]]; then add_optional datadog datadog datadog-secret api-key "$DD_API_KEY"; fi
if [[ -n "${GOOGLE_API_KEY:-}" ]]; then add_optional kagent kagent kagent-gemini GOOGLE_API_KEY "$GOOGLE_API_KEY"; fi

echo
echo "ArgoCD UI : kubectl -n argocd port-forward svc/argocd-server 8081:443  → https://localhost:8081"
echo "  user admin / pass: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
