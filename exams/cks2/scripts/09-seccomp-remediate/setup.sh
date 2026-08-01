#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace seccomp-audit --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /opt/cks2-seccomp

kubectl delete pod no-seccomp -n seccomp-audit --ignore-not-found

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: no-seccomp
  namespace: seccomp-audit
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: app
    image: nginx:alpine
EOF

echo "Pod no-seccomp exists in seccomp-audit with Unconfined seccomp — audit and remediate"
