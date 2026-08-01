#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace secured --dry-run=client -o yaml | kubectl apply -f -

kubectl run backend  -n secured --image=nginx:alpine --labels=app=backend  \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl run frontend -n secured --image=nginx:alpine --labels=app=frontend \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: pods backend and frontend in namespace secured"
