#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

HPA=$(kubectl get hpa load-gen-hpa -n hpa-demo -o json 2>/dev/null) || {
  echo "FAIL: HPA load-gen-hpa not found in hpa-demo"
  exit 1
}

TARGET=$(echo "$HPA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ref=d['spec'].get('scaleTargetRef',{})
print(ref.get('kind',''),ref.get('name',''))
")
if ! echo "$TARGET" | grep -q "Deployment load-gen"; then
  echo "FAIL: HPA does not target Deployment load-gen (got: $TARGET)"
  exit 1
fi

MIN=$(echo "$HPA" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('minReplicas',''))")
MAX=$(echo "$HPA" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('maxReplicas',''))")

if [[ "$MIN" != "2" ]]; then
  echo "FAIL: minReplicas should be 2 (got: $MIN)"
  exit 1
fi
if [[ "$MAX" != "8" ]]; then
  echo "FAIL: maxReplicas should be 8 (got: $MAX)"
  exit 1
fi

CPU=$(echo "$HPA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for m in d['spec'].get('metrics',[]):
    if m.get('type')=='Resource':
        r=m.get('resource',{})
        if r.get('name')=='cpu':
            t=r.get('target',{})
            print(t.get('averageUtilization',''))
            sys.exit(0)
# check v1 style
print(d['spec'].get('targetCPUUtilizationPercentage',''))
")
if [[ "$CPU" != "60" ]]; then
  echo "FAIL: CPU target utilization should be 60 (got: $CPU)"
  exit 1
fi

if [[ ! -f /opt/cka/load-gen-hpa.txt ]]; then
  echo "FAIL: /opt/cka/load-gen-hpa.txt not saved"
  exit 1
fi

echo "PASS: HPA load-gen-hpa correctly configured — min=2 max=8 cpu=60%; description saved"
