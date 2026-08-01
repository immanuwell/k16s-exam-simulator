#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-intra --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-intra run app --image=nginx:alpine --labels=app=web \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: namespace netpol-intra (auto-label kubernetes.io/metadata.name=netpol-intra present)"
