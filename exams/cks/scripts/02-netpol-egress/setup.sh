#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-egress --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-egress run cache --image=redis:alpine --labels=app=cache \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: namespace netpol-egress with cache pod (app=cache)"
