#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

kubectl create namespace crash-demo --dry-run=client -o yaml | kubectl apply -f -

# Pod that references a ConfigMap that does not exist — will CrashLoopBackOff
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  namespace: crash-demo
spec:
  restartPolicy: Always
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c"]
    args:
    - |
      if [ -z "$APP_ENV" ]; then
        echo "FATAL: APP_ENV not set — missing ConfigMap app-config" >&2
        exit 1
      fi
      echo "Running with APP_ENV=$APP_ENV LOG_LEVEL=$LOG_LEVEL"
      sleep 3600
    envFrom:
    - configMapRef:
        name: app-config
EOF

echo "Pod api-server created in namespace crash-demo (references missing ConfigMap app-config)"
