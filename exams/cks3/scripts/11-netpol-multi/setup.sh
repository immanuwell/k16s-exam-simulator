#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

for ns in netpol-multi dmz internal; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl -n netpol-multi run app1 --image=nginx:alpine --labels=app=app1 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dmz run client --image=nginx:alpine --labels=role=client \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n internal run db --image=nginx:alpine --labels=role=db \
  --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /opt/cks3-netpol

echo "Environment ready: namespaces netpol-multi, dmz, internal created (unlabelled)"
