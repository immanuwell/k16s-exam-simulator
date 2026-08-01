#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD=$(kubectl get pod manual-pod -n schedule-demo -o json 2>/dev/null) || {
  echo "FAIL: pod manual-pod not found in schedule-demo"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod manual-pod is not Running (phase: $PHASE)"
  exit 1
fi

NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "node01" ]]; then
  echo "FAIL: pod manual-pod is not on node01 (nodeName: $NODE)"
  exit 1
fi

[[ -f /opt/cka2/manual-schedule.txt ]] || {
  echo "FAIL: /opt/cka2/manual-schedule.txt not saved"
  exit 1
}

echo "PASS: pod manual-pod is Running on node01 (manually scheduled)"
