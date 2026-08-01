#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace seccomp-apps --dry-run=client -o yaml | kubectl apply -f -

# Create deployment without seccomp profile
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seccomp-app
  namespace: seccomp-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seccomp-app
  template:
    metadata:
      labels:
        app: seccomp-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
EOF

mkdir -p /opt/cks-seccomp
echo "Deployment seccomp-app created in namespace seccomp-apps (no seccomp profile)"
