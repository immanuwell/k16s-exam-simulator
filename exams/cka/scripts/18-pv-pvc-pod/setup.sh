#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka /mnt/exam-data
kubectl create namespace storage-demo --dry-run=client -o yaml | kubectl apply -f -

# Clean up any prior attempt
kubectl delete pvc data-pvc -n storage-demo 2>/dev/null || true
kubectl delete pod data-pod -n storage-demo 2>/dev/null || true
kubectl delete pv data-pv 2>/dev/null || true

echo "Namespace storage-demo ready; /mnt/exam-data created — provision PV, PVC, and Pod"
