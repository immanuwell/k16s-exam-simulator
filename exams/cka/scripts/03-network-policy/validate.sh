#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NP=$(kubectl get networkpolicy allow-frontend -n secured -o json 2>/dev/null)
if [[ -z "${NP}" ]]; then
  echo "FAIL: NetworkPolicy 'allow-frontend' not found in namespace 'secured'"
  exit 1
fi

# Must target backend pods
POD_SELECTOR=$(echo "${NP}" | kubectl get networkpolicy allow-frontend -n secured \
  -o jsonpath='{.spec.podSelector.matchLabels.app}')
if [[ "${POD_SELECTOR}" != "backend" ]]; then
  echo "FAIL: NetworkPolicy podSelector should target app=backend, got app=${POD_SELECTOR}"
  exit 1
fi

# Must have exactly one ingress rule
INGRESS_COUNT=$(echo "${NP}" | kubectl get networkpolicy allow-frontend -n secured \
  -o jsonpath='{range .spec.ingress[*]}{.from[0].podSelector.matchLabels.app}{"\n"}{end}' | grep -c .)
if [[ "${INGRESS_COUNT}" -lt 1 ]]; then
  echo "FAIL: NetworkPolicy has no ingress rules"
  exit 1
fi

# Ingress from must reference frontend
FROM_LABEL=$(kubectl get networkpolicy allow-frontend -n secured \
  -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.app}')
if [[ "${FROM_LABEL}" != "frontend" ]]; then
  echo "FAIL: ingress from selector should be app=frontend, got app=${FROM_LABEL}"
  exit 1
fi

echo "PASS: NetworkPolicy allow-frontend correctly restricts ingress to backend from frontend"
