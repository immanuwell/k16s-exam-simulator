#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

COREFILE=$(kubectl get configmap coredns -n kube-system \
  -o jsonpath='{.data.Corefile}' 2>/dev/null)

if ! echo "$COREFILE" | grep -q 'corp.internal'; then
  echo "FAIL: CoreDNS ConfigMap does not contain a corp.internal block"
  exit 1
fi

if ! echo "$COREFILE" | grep -q '192.168.100.1'; then
  echo "FAIL: CoreDNS ConfigMap does not forward corp.internal to 192.168.100.1"
  exit 1
fi

# Existing .:53 block must still be intact
if ! echo "$COREFILE" | grep -q '^\.:53\|^    .:53'; then
  echo "FAIL: CoreDNS ConfigMap is missing the original .:53 block — it was broken"
  exit 1
fi

# CoreDNS pods must be Running
RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns \
  --no-headers 2>/dev/null | awk '{print $3}' | grep -c 'Running' || true)
if [[ "$RUNNING" -eq 0 ]]; then
  echo "FAIL: CoreDNS pods are not Running after restart"
  exit 1
fi

if [[ ! -f /opt/cka/coredns-updated.yaml ]]; then
  echo "FAIL: /opt/cka/coredns-updated.yaml not saved"
  exit 1
fi

if ! grep -q 'corp.internal' /opt/cka/coredns-updated.yaml; then
  echo "FAIL: coredns-updated.yaml does not contain the corp.internal stub zone"
  exit 1
fi

echo "PASS: CoreDNS stub zone for corp.internal→192.168.100.1 configured; pods Running; YAML saved"
