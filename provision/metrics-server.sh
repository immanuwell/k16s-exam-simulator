#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "metrics-server"

already_done "metrics-server" && { log_skip "metrics-server"; exit 0; }

export KUBECONFIG=/etc/kubernetes/admin.conf
METRICS_SERVER_VERSION="${K16S_METRICS_SERVER_VERSION:-v0.9.0}"

log_info "Installing metrics-server ${METRICS_SERVER_VERSION}..."

kubectl apply -f \
  "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

# Kubelet serving certs on a kubeadm cluster are self-signed and not in a CA
# metrics-server trusts (unlike EKS/GKE, where the cloud provider issues
# them) — without --kubelet-insecure-tls, every scrape fails TLS verification
# and `kubectl top` reports "Metrics API not available" forever.
if ! kubectl get deploy metrics-server -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[0].args}' \
    | grep -q -- "--kubelet-insecure-tls"; then
  kubectl patch deployment metrics-server -n kube-system --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
  ]'
fi

log_info "Waiting for metrics-server to become available (up to 2 min)..."
kubectl wait --for=condition=Available deploy/metrics-server \
  -n kube-system --timeout=120s \
  || log_warn "metrics-server not Available yet — kubectl top may need another minute to start returning data"

log_ok "metrics-server ready"
mark_done "metrics-server"
