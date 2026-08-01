#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

for node in node01 node02; do
  LABEL=$(kubectl get node $node -o jsonpath='{.metadata.labels.monitoring}' 2>/dev/null)
  if [[ "$LABEL" != "enabled" ]]; then
    echo "FAIL: node $node does not have label monitoring=enabled (got: '$LABEL')"
    exit 1
  fi
done

DS=$(kubectl get daemonset log-agent -n monitoring -o json 2>/dev/null) || {
  echo "FAIL: DaemonSet log-agent not found in namespace monitoring"
  exit 1
}

# nodeSelector must be monitoring=enabled
NS=$(echo "$DS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d['spec']['template']['spec'].get('nodeSelector',{}).get('monitoring',''))
")
if [[ "$NS" != "enabled" ]]; then
  echo "FAIL: DaemonSet nodeSelector does not have monitoring=enabled (got: $NS)"
  exit 1
fi

# DaemonSet must have at least 2 pods Running (node01 and node02 are labeled)
DESIRED=$(echo "$DS" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('desiredNumberScheduled',0))")
READY=$(echo "$DS" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('numberReady',0))")
if [[ "$DESIRED" -lt 2 ]]; then
  echo "FAIL: DaemonSet desiredNumberScheduled is $DESIRED (expected at least 2)"
  exit 1
fi
if [[ "$READY" -lt 2 ]]; then
  echo "FAIL: DaemonSet only $READY/$DESIRED pods ready"
  exit 1
fi

if [[ ! -f /opt/cka/log-agent.yaml ]]; then
  echo "FAIL: /opt/cka/log-agent.yaml not saved"
  exit 1
fi

echo "PASS: DaemonSet log-agent running on $READY labeled nodes; YAML saved"
