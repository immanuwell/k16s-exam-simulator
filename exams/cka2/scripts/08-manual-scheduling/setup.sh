#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace schedule-demo --dry-run=client -o yaml | kubectl apply -f -

# Clean up prior attempts
kubectl delete pod manual-pod -n schedule-demo 2>/dev/null || true

# Pod with a non-existent schedulerName → stays Pending forever
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: manual-pod
  namespace: schedule-demo
spec:
  schedulerName: my-custom-scheduler
  containers:
  - name: app
    image: nginx:alpine
  restartPolicy: Never
EOF

echo "Pod manual-pod created with schedulerName=my-custom-scheduler — will remain Pending"
