#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka
kubectl create namespace sidecar-demo --dry-run=client -o yaml | kubectl apply -f -

echo "Namespace sidecar-demo ready — create pod log-sidecar with app and log-shipper containers"
