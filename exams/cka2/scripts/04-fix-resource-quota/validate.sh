#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

DEPLOY=$(kubectl get deployment quota-app -n quota-demo -o json 2>/dev/null) || {
  echo "FAIL: deployment quota-app not found in quota-demo"
  exit 1
}

CPU_REQ=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['spec']['template']['spec']['containers'][0]
print(c.get('resources', {}).get('requests', {}).get('cpu', 'missing'))
")

MEM_REQ=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['spec']['template']['spec']['containers'][0]
print(c.get('resources', {}).get('requests', {}).get('memory', 'missing'))
")

if [[ "$CPU_REQ" == "missing" ]]; then
  echo "FAIL: no cpu request set on quota-app containers"
  exit 1
fi

if [[ "$MEM_REQ" == "missing" ]]; then
  echo "FAIL: no memory request set on quota-app containers"
  exit 1
fi

# Wait for pods to be Running (up to 90s)
for i in $(seq 1 18); do
  READY=$(kubectl get deployment quota-app -n quota-demo \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [[ "${READY:-0}" -ge 3 ]] && break
  [[ $i -eq 18 ]] && {
    echo "FAIL: quota-app only has ${READY:-0}/3 pods ready after 90s"
    exit 1
  }
  sleep 5
done

[[ -f /opt/cka2/quota-fix.txt ]] || {
  echo "FAIL: /opt/cka2/quota-fix.txt not saved"
  exit 1
}

echo "PASS: quota-app has resource requests (cpu=$CPU_REQ, memory=$MEM_REQ) and all 3 replicas are Running"
