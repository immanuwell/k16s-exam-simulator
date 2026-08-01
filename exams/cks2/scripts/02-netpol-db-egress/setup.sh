#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-db-egress --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace data-store --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-db-egress run backend --image=nginx:alpine --labels=app=backend \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n data-store run db --image=nginx:alpine --labels=app=db \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: netpol-db-egress (pod app=backend), data-store (pod app=db, unlabelled namespace)"
