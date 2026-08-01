#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2/charts/webapp/templates

# Install Helm if not present
if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Create a simple self-contained chart (no internet needed)
cat > /opt/cka2/charts/webapp/Chart.yaml << 'EOF'
apiVersion: v2
name: webapp
description: Exam practice Helm chart
type: application
version: 1.0.0
appVersion: "1.0"
EOF

cat > /opt/cka2/charts/webapp/values.yaml << 'EOF'
replicaCount: 1
image:
  repository: nginx
  tag: alpine
service:
  type: ClusterIP
  port: 80
EOF

cat > /opt/cka2/charts/webapp/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-webapp
  labels:
    app.kubernetes.io/name: {{ .Release.Name }}-webapp
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-webapp
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-webapp
    spec:
      containers:
      - name: webapp
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
        ports:
        - containerPort: 80
EOF

cat > /opt/cka2/charts/webapp/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-webapp
  labels:
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  type: {{ .Values.service.type }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: 80
  selector:
    app: {{ .Release.Name }}-webapp
EOF

# Clean up prior helm release if any
helm uninstall webapp -n helm-demo 2>/dev/null || true
kubectl delete namespace helm-demo 2>/dev/null || true

echo "Helm chart ready at /opt/cka2/charts/webapp/"
echo "Tasks: helm template (--skip-crds), helm install (--skip-crds --create-namespace -n helm-demo)"
