#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace priority-demo --dry-run=client -o yaml | kubectl apply -f -

# Clean up prior attempts
kubectl delete priorityclass high-priority-apps 2>/dev/null || true
kubectl delete deployment priority-web -n priority-demo 2>/dev/null || true

echo "Namespace priority-demo ready — create PriorityClass and Deployment"
