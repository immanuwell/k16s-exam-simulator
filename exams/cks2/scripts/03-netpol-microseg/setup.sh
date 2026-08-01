#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-internal --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-internal run worker --image=nginx:alpine --labels=role=worker \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-internal run api --image=nginx:alpine --labels=role=api \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-internal run metrics --image=nginx:alpine --labels=role=metrics \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: netpol-internal with pods role=worker, role=api, role=metrics"
