#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

STATUS=$(kubectl get node node01 --no-headers 2>/dev/null | awk '{print $2}')
if [[ "$STATUS" != "Ready" ]]; then
  echo "FAIL: node01 is not Ready (status: $STATUS) — restart kubelet on node01: ssh node01; systemctl start kubelet"
  exit 1
fi

KUBELET=$(incus exec node01 -- systemctl is-active kubelet 2>/dev/null || true)
if [[ "$KUBELET" != "active" ]]; then
  echo "FAIL: kubelet on node01 is not active (got: $KUBELET)"
  exit 1
fi

if [[ ! -f /opt/cka/node01-fix.txt ]]; then
  echo "FAIL: /opt/cka/node01-fix.txt not saved"
  exit 1
fi

echo "PASS: node01 is Ready and kubelet is running; fix file saved"
