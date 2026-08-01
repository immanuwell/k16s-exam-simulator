#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka
kubectl create namespace ingress-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ingress-demo create deployment web-deploy --image=nginx:alpine \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ingress-demo create deployment api-deploy --image=nginx:alpine \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ingress-demo expose deployment web-deploy \
  --name=web-svc --port=80 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ingress-demo expose deployment api-deploy \
  --name=api-svc --port=8080 --target-port=80 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Services web-svc:80 and api-svc:8080 ready in namespace ingress-demo"
