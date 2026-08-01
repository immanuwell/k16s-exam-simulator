#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace svc-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment web-app -n svc-demo 2>/dev/null || true
kubectl delete service web-svc -n svc-demo 2>/dev/null || true

# Deployment without a named port
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: svc-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

echo "Deployment web-app created without named port — add name 'http' and create NodePort Service"
