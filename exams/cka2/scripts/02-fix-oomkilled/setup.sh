#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace mem-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mem-hog
  namespace: mem-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mem-hog
  template:
    metadata:
      labels:
        app: mem-hog
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            memory: "2Mi"
          limits:
            memory: "2Mi"
EOF

echo "Deployment mem-hog created with 2Mi memory limit (will OOMKill nginx)"
