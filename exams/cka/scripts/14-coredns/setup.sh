#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Remove stub zone if it already exists from a prior run
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' \
  | grep -v 'corp.internal' \
  | kubectl create configmap coredns \
      --from-file=Corefile=/dev/stdin \
      -n kube-system \
      --dry-run=client -o yaml \
  | kubectl apply -f - 2>/dev/null || true

echo "CoreDNS ConfigMap reset — add the corp.internal stub zone"
