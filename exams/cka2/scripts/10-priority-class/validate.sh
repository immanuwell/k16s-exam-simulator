#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PC=$(kubectl get priorityclass high-priority-apps -o json 2>/dev/null) || {
  echo "FAIL: PriorityClass high-priority-apps not found"
  exit 1
}

VALUE=$(echo "$PC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('value', 0))")
if [[ "$VALUE" -ne 1000000 ]]; then
  echo "FAIL: PriorityClass value is $VALUE (expected 1000000)"
  exit 1
fi

GLOBAL=$(echo "$PC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('globalDefault', True))")
if [[ "$GLOBAL" == "True" ]]; then
  echo "FAIL: PriorityClass globalDefault should be false"
  exit 1
fi

DEPLOY=$(kubectl get deployment priority-web -n priority-demo -o json 2>/dev/null) || {
  echo "FAIL: deployment priority-web not found in priority-demo"
  exit 1
}

PC_NAME=$(echo "$DEPLOY" | python3 -c "
import sys, json
print(json.load(sys.stdin)['spec']['template']['spec'].get('priorityClassName', 'missing'))
")
if [[ "$PC_NAME" != "high-priority-apps" ]]; then
  echo "FAIL: deployment priority-web does not use priorityClassName=high-priority-apps (got: $PC_NAME)"
  exit 1
fi

# Check pods are running
READY=$(kubectl get deployment priority-web -n priority-demo \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "FAIL: no ready replicas for priority-web"
  exit 1
fi

[[ -f /opt/cka2/priority-class.yaml ]] || {
  echo "FAIL: /opt/cka2/priority-class.yaml not saved"
  exit 1
}

echo "PASS: PriorityClass high-priority-apps (value=1000000) created and priority-web deployment uses it"
