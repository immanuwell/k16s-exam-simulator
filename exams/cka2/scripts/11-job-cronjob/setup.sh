#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace batch-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job db-backup -n batch-demo 2>/dev/null || true
kubectl delete cronjob cleanup-logs -n batch-demo 2>/dev/null || true

echo "Namespace batch-demo ready — create Job db-backup and CronJob cleanup-logs"
