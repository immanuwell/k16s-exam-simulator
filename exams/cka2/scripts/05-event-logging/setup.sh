#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace event-demo --dry-run=client -o yaml | kubectl apply -f -

# Create a pod that will keep failing (bad image tag → ImagePullBackOff)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: problem-pod
  namespace: event-demo
  labels:
    app: problem
spec:
  containers:
  - name: app
    image: nginx:this-tag-does-not-exist-exam
  restartPolicy: Never
EOF

echo "problem-pod created with invalid image — will generate Warning events"
