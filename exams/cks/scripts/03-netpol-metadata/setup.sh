#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-metadata --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-metadata run web --image=nginx:alpine --labels=app=web \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks-netpol
echo "Environment ready: namespace netpol-metadata with web pod"
