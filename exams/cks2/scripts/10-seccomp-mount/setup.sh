#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace seccomp-mount --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /var/lib/kubelet/seccomp/profiles /opt/cks2-seccomp

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mount-block
  namespace: seccomp-mount
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mount-block
  template:
    metadata:
      labels:
        app: mount-block
    spec:
      nodeName: controlplane
      containers:
      - name: app
        image: nginx:alpine
EOF

echo "Deployment mount-block ready in seccomp-mount — create block-mount.json and apply to deployment"
