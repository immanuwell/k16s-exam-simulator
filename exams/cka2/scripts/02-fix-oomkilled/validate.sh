#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

DEPLOY=$(kubectl get deployment mem-hog -n mem-demo -o json 2>/dev/null) || {
  echo "FAIL: deployment mem-hog not found in mem-demo"
  exit 1
}

MEM_LIMIT=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['spec']['template']['spec']['containers'][0]
print(c.get('resources', {}).get('limits', {}).get('memory', 'missing'))
")

MEM_REQ=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['spec']['template']['spec']['containers'][0]
print(c.get('resources', {}).get('requests', {}).get('memory', 'missing'))
")

# Parse value to bytes for comparison (accepts Mi suffix)
parse_mi() {
  echo "$1" | python3 -c "
import sys, re
v = sys.stdin.read().strip()
m = re.match(r'^(\d+)Mi$', v)
print(int(m.group(1)) if m else 0)
"
}

LIMIT_MI=$(parse_mi "$MEM_LIMIT")
REQ_MI=$(parse_mi "$MEM_REQ")

if [[ "$LIMIT_MI" -lt 64 ]]; then
  echo "FAIL: memory limit is $MEM_LIMIT — must be at least 64Mi (got ${LIMIT_MI}Mi)"
  exit 1
fi

if [[ "$REQ_MI" -lt 32 ]]; then
  echo "FAIL: memory request is $MEM_REQ — must be at least 32Mi (got ${REQ_MI}Mi)"
  exit 1
fi

# Wait for the pod to be Running (up to 90s)
for i in $(seq 1 18); do
  PHASE=$(kubectl get pods -n mem-demo -l app=mem-hog \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  [[ "$PHASE" == "Running" ]] && break
  [[ $i -eq 18 ]] && {
    echo "FAIL: pod is not Running after 90s (phase: $PHASE)"
    exit 1
  }
  sleep 5
done

[[ -f /opt/cka2/oomkilled-fix.txt ]] || {
  echo "FAIL: /opt/cka2/oomkilled-fix.txt not saved"
  exit 1
}

echo "PASS: mem-hog deployment has adequate memory (limit: $MEM_LIMIT, request: $MEM_REQ) and pod is Running"
