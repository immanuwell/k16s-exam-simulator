#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-web --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace monitoring team=monitoring --overwrite

kubectl -n netpol-web run backend --image=nginx:alpine --labels=app=backend \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks-netpol
echo "Environment ready: namespace netpol-web with pod backend; monitoring namespace labelled team=monitoring"
