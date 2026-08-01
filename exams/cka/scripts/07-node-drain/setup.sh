#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Ensure node01 is uncordoned before the task starts
kubectl uncordon node01 2>/dev/null || true

# Create a workload so there's something to drain
kubectl create namespace drain-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl -n drain-demo create deployment web --image=nginx:alpine --replicas=2 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: node01 is schedulable; drain-demo/web deployment running"
