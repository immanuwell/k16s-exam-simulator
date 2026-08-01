#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka
kubectl create namespace netpol-app --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-app run frontend --image=nginx:alpine --labels=tier=frontend \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-app run backend --image=nginx:alpine --labels=tier=backend \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Namespace netpol-app ready with pods tier=frontend and tier=backend"
