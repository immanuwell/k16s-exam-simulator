#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-external --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-external run client --image=nginx:alpine --labels=app=client \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks3-netpol

echo "Environment ready: namespace netpol-external with pod app=client"
