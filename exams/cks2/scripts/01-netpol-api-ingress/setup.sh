#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-cross --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ops-tools --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-cross run api --image=nginx:alpine --labels=app=api \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-cross run frontend --image=nginx:alpine --labels=role=frontend \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: namespace netpol-cross with pods app=api and role=frontend; namespace ops-tools exists (unlabelled)"
