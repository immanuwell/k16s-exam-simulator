#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Calico CNI"

already_done "cni" && { log_skip "Calico CNI"; exit 0; }

export KUBECONFIG=/root/.kube/config
POD_CIDR="${CKX_POD_CIDR:-10.244.0.0/16}"
CALICO_VERSION="${CKX_CALICO_VERSION:-v3.29.1}"

log_info "Installing Calico ${CALICO_VERSION} via Tigera operator..."

kubectl apply -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
  2>&1 | grep -v "^$" || true

kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

log_info "Waiting for Calico to become ready (up to 3 min)..."
kubectl wait --for=condition=Ready pods \
  -n calico-system --all \
  --timeout=180s 2>/dev/null || true

kubectl wait --for=condition=Available deploy/coredns \
  -n kube-system \
  --timeout=120s

log_ok "Calico CNI ready"
mark_done "cni"
