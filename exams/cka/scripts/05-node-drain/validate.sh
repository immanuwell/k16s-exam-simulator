#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

STATUS=$(kubectl get node node01 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [[ "${STATUS}" != "True" ]]; then
  echo "FAIL: node01 Ready condition is '${STATUS}', expected 'True'"
  exit 1
fi

UNSCHEDULABLE=$(kubectl get node node01 -o jsonpath='{.spec.unschedulable}')
if [[ "${UNSCHEDULABLE}" == "true" ]]; then
  echo "FAIL: node01 is still marked unschedulable — run: kubectl uncordon node01"
  exit 1
fi

# No NoSchedule taint from cordon should remain
TAINT=$(kubectl get node node01 -o jsonpath='{range .spec.taints[*]}{.effect}{"\n"}{end}' | grep "NoSchedule" || true)
if [[ -n "${TAINT}" ]]; then
  echo "FAIL: node01 still has a NoSchedule taint"
  exit 1
fi

echo "PASS: node01 is Ready and schedulable"
