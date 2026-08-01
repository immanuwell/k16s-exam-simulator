#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

DEPLOY=$(kubectl get deployment web-app -n svc-demo -o json 2>/dev/null) || {
  echo "FAIL: deployment web-app not found in svc-demo"
  exit 1
}

PORT_NAME=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ports = d['spec']['template']['spec']['containers'][0].get('ports', [])
for p in ports:
    if p.get('containerPort') == 80:
        print(p.get('name', 'unnamed')); exit()
print('missing')
")
if [[ "$PORT_NAME" != "http" ]]; then
  echo "FAIL: containerPort 80 does not have name 'http' (got: $PORT_NAME)"
  exit 1
fi

SVC=$(kubectl get service web-svc -n svc-demo -o json 2>/dev/null) || {
  echo "FAIL: Service web-svc not found in svc-demo"
  exit 1
}

SVC_TYPE=$(echo "$SVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['type'])")
if [[ "$SVC_TYPE" != "NodePort" ]]; then
  echo "FAIL: Service web-svc type is $SVC_TYPE (expected NodePort)"
  exit 1
fi

TARGET=$(echo "$SVC" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['spec']['ports'][0].get('targetPort', 'missing'))
")
if [[ "$TARGET" != "http" ]]; then
  echo "FAIL: Service targetPort is '$TARGET' (must be 'http' — the named port)"
  exit 1
fi

NODE_PORT=$(echo "$SVC" | python3 -c "
import sys, json
print(json.load(sys.stdin)['spec']['ports'][0].get('nodePort', 0))
")
if [[ "${NODE_PORT:-0}" -lt 30000 ]]; then
  echo "FAIL: Service has no valid nodePort assigned (got: $NODE_PORT)"
  exit 1
fi

# Check endpoints exist
EP=$(kubectl get endpoints web-svc -n svc-demo -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "")
[[ -n "$EP" && "$EP" != "null" ]] || {
  echo "FAIL: Service web-svc has no endpoints"
  exit 1
}

[[ -f /opt/cka2/nodeport.txt ]] || {
  echo "FAIL: /opt/cka2/nodeport.txt not saved"
  exit 1
}

echo "PASS: Deployment web-app port named 'http'; Service web-svc (NodePort $NODE_PORT, targetPort=http) with endpoints"
