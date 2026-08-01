#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace storage-test --dry-run=client -o yaml | kubectl apply -f -

kubectl delete storageclass fast-storage 2>/dev/null || true
kubectl delete pvc test-claim -n storage-test 2>/dev/null || true

echo "No default StorageClass exists — create fast-storage with WaitForFirstConsumer and set as default"
