#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

kubectl create namespace scheduling-demo --dry-run=client -o yaml | kubectl apply -f -

# Remove label if it already exists from a prior run
kubectl label node node02 accelerator- --overwrite 2>/dev/null || true

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
  namespace: scheduling-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gpu-workload
  template:
    metadata:
      labels:
        app: gpu-workload
    spec:
      nodeSelector:
        accelerator: nvidia-gpu
      containers:
      - name: workload
        image: nginx:alpine
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
EOF

echo "Deployment gpu-workload created — pods will be Pending because no node has label accelerator=nvidia-gpu"
