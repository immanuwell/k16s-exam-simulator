#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka
kubectl create namespace rbac-demo --dry-run=client -o yaml | kubectl apply -f -

echo "Namespace rbac-demo ready — create SA, Role, and RoleBinding"
