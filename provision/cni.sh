#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Calico CNI"

already_done "cni" && { log_skip "Calico CNI"; exit 0; }

export KUBECONFIG=/root/.kube/config
POD_CIDR="${K16S_POD_CIDR:-10.244.0.0/16}"
CALICO_VERSION="${K16S_CALICO_VERSION:-v3.29.1}"

log_info "Installing Calico ${CALICO_VERSION} via Tigera operator..."

# Server-side apply is required here: the installations.operator.tigera.io CRD
# is larger than the 262144-byte ceiling on the kubectl.kubernetes.io/last-applied-
# configuration annotation that client-side apply writes, so a plain `kubectl apply`
# fails to create it. The failure is invisible at this line (it is swallowed by the
# `|| true` that tolerates re-runs), and only surfaces further down as
# "no matches for kind Installation" — which aborts the whole provisioner.
kubectl apply --server-side --force-conflicts -f \
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
