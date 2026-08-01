#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace netpol-logs --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

kubectl -n netpol-logs run collector --image=nginx:alpine --labels=app=collector \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-logs run shipper --image=nginx:alpine --labels=role=shipper \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: netpol-logs (pods app=collector, role=shipper), namespace logging (unlabelled)"
