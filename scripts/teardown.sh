#!/usr/bin/env bash
# terraform destroy の前に実行。PVC 由来のディスクはクラスタ削除後も残り課金され続けるため先に消す
set -euo pipefail

# ArgoCD の自動復元を止める (root → 子の順)
kubectl -n argocd delete application root --ignore-not-found
kubectl -n argocd delete applications --all

# PVC (= GCE ディスク) / LB を持つ namespace を削除
kubectl delete namespace todo istio-ingress --ignore-not-found --wait

echo "残存ディスク確認 (未使用のものがあれば削除):"
gcloud compute disks list --filter="-users:*" --format="table(name,zone,sizeGb)"
