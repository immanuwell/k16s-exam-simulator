#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace webns --dry-run=client -o yaml | kubectl apply -f -
kubectl create deployment web-app --image=nginx:alpine --replicas=1 -n webns \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: deployment web-app in namespace webns (1 replica)"
