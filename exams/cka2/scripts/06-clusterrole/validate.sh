#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get serviceaccount node-inspector -n inspect-ns &>/dev/null || {
  echo "FAIL: ServiceAccount node-inspector not found in namespace inspect-ns"
  exit 1
}

CR=$(kubectl get clusterrole node-reader -o json 2>/dev/null) || {
  echo "FAIL: ClusterRole node-reader not found"
  exit 1
}

# Check rules include nodes and nodes/status with get/list/watch
RULES_OK=$(echo "$CR" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d.get('rules', []):
    res = rule.get('resources', [])
    verbs = rule.get('verbs', [])
    if 'nodes' in res and all(v in verbs for v in ['get','list','watch']):
        print('ok'); break
else:
    print('missing')
")

if [[ "$RULES_OK" != "ok" ]]; then
  echo "FAIL: ClusterRole node-reader does not have get/list/watch on nodes"
  exit 1
fi

CRB=$(kubectl get clusterrolebinding node-inspector-binding -o json 2>/dev/null) || {
  echo "FAIL: ClusterRoleBinding node-inspector-binding not found"
  exit 1
}

BOUND_SA=$(echo "$CRB" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for s in d.get('subjects', []):
    if s.get('name') == 'node-inspector' and s.get('namespace') == 'inspect-ns':
        print('ok'); break
else:
    print('missing')
")

if [[ "$BOUND_SA" != "ok" ]]; then
  echo "FAIL: ClusterRoleBinding does not bind node-inspector SA in inspect-ns"
  exit 1
fi

CAN_LIST=$(kubectl auth can-i list nodes \
  --as=system:serviceaccount:inspect-ns:node-inspector 2>/dev/null)
if [[ "$CAN_LIST" != "yes" ]]; then
  echo "FAIL: node-inspector cannot list nodes (got: $CAN_LIST)"
  exit 1
fi

CAN_DELETE=$(kubectl auth can-i delete nodes \
  --as=system:serviceaccount:inspect-ns:node-inspector 2>/dev/null)
if [[ "$CAN_DELETE" != "no" ]]; then
  echo "FAIL: node-inspector should NOT be able to delete nodes (got: $CAN_DELETE)"
  exit 1
fi

[[ -f /opt/cka2/node-inspector-check.txt ]] || {
  echo "FAIL: /opt/cka2/node-inspector-check.txt not saved"
  exit 1
}

echo "PASS: ClusterRole node-reader + ClusterRoleBinding + SA node-inspector correct; can list but not delete nodes"
