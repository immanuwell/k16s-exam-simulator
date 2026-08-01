#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

REPLICAS=$(kubectl get deployment web-app -n webns -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [[ "${REPLICAS}" != "4" ]]; then
  echo "FAIL: expected 4 replicas, got '${REPLICAS}'"
  exit 1
fi

READY=$(kubectl get deployment web-app -n webns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [[ "${READY}" != "4" ]]; then
  echo "FAIL: only ${READY}/4 replicas are ready — wait for rollout to complete"
  exit 1
fi

echo "PASS: deployment web-app has 4/4 ready replicas"
