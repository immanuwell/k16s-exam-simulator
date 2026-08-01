#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace inspect-ns --dry-run=client -o yaml | kubectl apply -f -

# Remove any prior attempt to ensure idempotency
kubectl delete clusterrolebinding node-inspector-binding 2>/dev/null || true
kubectl delete clusterrole node-reader 2>/dev/null || true
kubectl delete serviceaccount node-inspector -n inspect-ns 2>/dev/null || true

echo "Namespace inspect-ns ready — create ServiceAccount, ClusterRole, and ClusterRoleBinding"
