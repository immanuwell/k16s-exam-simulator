#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ops-team --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-staging run web --image=nginx:alpine --labels=app=web \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks3-netpol

echo "Environment ready: namespaces netpol-staging and ops-team created"
