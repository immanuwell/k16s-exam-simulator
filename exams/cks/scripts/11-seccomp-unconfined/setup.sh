#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace seccomp-fix --dry-run=client -o yaml | kubectl apply -f -

# Delete any existing pod first to ensure clean state
kubectl delete pod unconfined-pod -n seccomp-fix --ignore-not-found=true

# Create pod with Unconfined seccomp
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unconfined-pod
  namespace: seccomp-fix
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: app
    image: nginx:alpine
EOF

mkdir -p /opt/cks-seccomp
echo "Pod unconfined-pod created in namespace seccomp-fix with seccomp Unconfined"
