#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace selector-demo --dry-run=client -o yaml | kubectl apply -f -

# Deployment: pods have label app=backend-v2
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: selector-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend-v2
  template:
    metadata:
      labels:
        app: backend-v2
        version: "2"
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

# Service: selector targets app=backend-v1 (intentionally wrong)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: selector-demo
spec:
  selector:
    app: backend-v1
  ports:
  - port: 80
    targetPort: 80
EOF

echo "Deployment uses label app=backend-v2 but service selects app=backend-v1 — no endpoints"
