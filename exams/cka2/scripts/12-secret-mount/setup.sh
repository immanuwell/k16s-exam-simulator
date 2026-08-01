#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace secret-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl delete secret app-credentials -n secret-demo 2>/dev/null || true
kubectl delete pod secret-consumer -n secret-demo 2>/dev/null || true

echo "Namespace secret-demo ready — create Secret app-credentials and Pod secret-consumer"
