#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod-apps --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-prod run payments --image=nginx:alpine --labels=app=payments \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n prod-apps run client --image=nginx:alpine --labels=access=allowed \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks3-netpol

echo "Environment ready: namespaces netpol-prod and prod-apps created; pod payments in netpol-prod"
