#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Manifest must exist on node01
MANIFEST=$(incus exec node01 -- cat /etc/kubernetes/manifests/static-busybox.yaml 2>/dev/null) || {
  echo "FAIL: /etc/kubernetes/manifests/static-busybox.yaml not found on node01"
  exit 1
}

if ! echo "$MANIFEST" | grep -q 'busybox'; then
  echo "FAIL: manifest does not reference busybox image"
  exit 1
fi

# Pod must appear in the API server
for i in {1..12}; do
  PHASE=$(kubectl get pod static-busybox-node01 -n default \
    -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && break
  sleep 5
done

PHASE=$(kubectl get pod static-busybox-node01 -n default \
  -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod static-busybox-node01 is not Running (phase: $PHASE)"
  exit 1
fi

# Check it runs on node01
NODE=$(kubectl get pod static-busybox-node01 -n default \
  -o jsonpath='{.spec.nodeName}' 2>/dev/null)
if [[ "$NODE" != "node01" ]]; then
  echo "FAIL: pod is not on node01 (nodeName: $NODE)"
  exit 1
fi

if [[ ! -f /opt/cka/static-pod-name.txt ]]; then
  echo "FAIL: /opt/cka/static-pod-name.txt not saved"
  exit 1
fi

if ! grep -q 'static-busybox-node01' /opt/cka/static-pod-name.txt; then
  echo "FAIL: static-pod-name.txt should contain 'static-busybox-node01'"
  exit 1
fi

echo "PASS: static-busybox-node01 is Running on node01; name saved"
