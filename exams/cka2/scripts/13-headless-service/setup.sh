#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace headless-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl delete statefulset db -n headless-demo 2>/dev/null || true
kubectl delete service db-headless -n headless-demo 2>/dev/null || true

echo "Namespace headless-demo ready — create headless Service db-headless and StatefulSet db"
