#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2/kustomize/base
mkdir -p /opt/cka2/kustomize/overlays/production

cat > /opt/cka2/kustomize/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

cat > /opt/cka2/kustomize/base/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
EOF

cat > /opt/cka2/kustomize/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF

cat > /opt/cka2/kustomize/overlays/production/replica-patch.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
EOF

cat > /opt/cka2/kustomize/overlays/production/label-patch.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    env: production
spec:
  template:
    metadata:
      labels:
        env: production
EOF

cat > /opt/cka2/kustomize/overlays/production/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustomize-demo
resources:
  - ../../base
patches:
  - path: replica-patch.yaml
  - path: label-patch.yaml
EOF

kubectl create namespace kustomize-demo --dry-run=client -o yaml | kubectl apply -f -

echo "Kustomize base and production overlay created at /opt/cka2/kustomize/"
