#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

SVC=$(kubectl get service backend-svc -n selector-demo -o json 2>/dev/null) || {
  echo "FAIL: service backend-svc not found in selector-demo"
  exit 1
}

SELECTOR=$(echo "$SVC" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['spec'].get('selector', {}).get('app', 'missing'))
")

if [[ "$SELECTOR" != "backend-v2" ]]; then
  echo "FAIL: service selector app=$SELECTOR (should be backend-v2)"
  exit 1
fi

# Check endpoints are populated
EP_COUNT=$(kubectl get endpoints backend-svc -n selector-demo \
  -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | python3 -c "
import sys, json
data = sys.stdin.read().strip()
print(len(json.loads(data)) if data else 0)
" 2>/dev/null || echo "0")

if [[ "$EP_COUNT" -lt 1 ]]; then
  echo "FAIL: service backend-svc still has no endpoints (selector fixed but pods may not be ready)"
  exit 1
fi

[[ -f /opt/cka2/service-fix.txt ]] || {
  echo "FAIL: /opt/cka2/service-fix.txt not saved"
  exit 1
}

echo "PASS: service backend-svc selector fixed (app=backend-v2) and has $EP_COUNT endpoint(s)"
