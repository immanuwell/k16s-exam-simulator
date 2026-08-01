#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-proxy --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace edge --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-proxy run proxy --image=nginx:alpine --labels=app=proxy \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: netpol-proxy (pod app=proxy), namespace edge exists (unlabelled)"
