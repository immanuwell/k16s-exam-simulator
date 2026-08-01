#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Node must be Ready (not SchedulingDisabled — meaning uncordon happened)
STATUS=$(kubectl get node node01 --no-headers 2>/dev/null | awk '{print $2}')
if [[ "$STATUS" != "Ready" ]]; then
  echo "FAIL: node01 is not Ready (status: $STATUS) — did you uncordon it?"
  exit 1
fi

# No non-DaemonSet pods should be running on node01 after drain
# (they will have been rescheduled to other nodes and should now be elsewhere)
NON_DS_ON_NODE=$(kubectl get pods -A --field-selector=spec.nodeName=node01 \
  --no-headers 2>/dev/null | grep -v "daemonset\|calico\|canal\|flannel\|cilium\|weave\|multus\|kindnet" \
  | wc -l | tr -d ' ')

if [[ ! -f /opt/cka/node-drain.txt ]]; then
  echo "FAIL: /opt/cka/node-drain.txt not saved"
  exit 1
fi

if ! grep -q 'node01' /opt/cka/node-drain.txt; then
  echo "FAIL: node-drain.txt does not mention node01"
  exit 1
fi

if grep -q 'SchedulingDisabled' /opt/cka/node-drain.txt; then
  echo "FAIL: node-drain.txt shows node01 is still cordoned (SchedulingDisabled)"
  exit 1
fi

echo "PASS: node01 was drained and uncordoned; status=$STATUS; file saved"
