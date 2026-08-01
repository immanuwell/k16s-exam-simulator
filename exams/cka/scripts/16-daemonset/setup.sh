#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Remove label if it exists from a prior run
kubectl label node node01 monitoring- 2>/dev/null || true
kubectl label node node02 monitoring- 2>/dev/null || true

echo "Namespace monitoring ready; monitoring label removed from nodes — add it and create the DaemonSet"
