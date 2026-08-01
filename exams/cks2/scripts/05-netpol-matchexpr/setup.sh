#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-expressions --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-expressions run backend --image=nginx:alpine --labels=app=backend \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-expressions run frontend --image=nginx:alpine --labels=tier=frontend \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-expressions run api --image=nginx:alpine --labels=tier=api \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: netpol-expressions with pods app=backend, tier=frontend, tier=api"
