#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

GW=$(kubectl get gateway main-gateway -n gateway-demo -o json 2>/dev/null) || {
  echo "FAIL: Gateway main-gateway not found in gateway-demo"
  exit 1
}

# Verify listener name=http, port=80
LISTENER=$(echo "$GW" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for l in d['spec'].get('listeners',[]):
    if l.get('name')=='http' and l.get('port')==80 and l.get('protocol')=='HTTP':
        print('ok'); sys.exit(0)
print('missing')
")
if [[ "$LISTENER" != "ok" ]]; then
  echo "FAIL: Gateway main-gateway does not have listener name=http, port=80, protocol=HTTP"
  exit 1
fi

ROUTE=$(kubectl get httproute app-route -n gateway-demo -o json 2>/dev/null) || {
  echo "FAIL: HTTPRoute app-route not found in gateway-demo"
  exit 1
}

# Hostname must be app.example.com
HOSTNAME=$(echo "$ROUTE" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d['spec'].get('hostnames',[''])[0])
")
if [[ "$HOSTNAME" != "app.example.com" ]]; then
  echo "FAIL: HTTPRoute hostname is not app.example.com (got: $HOSTNAME)"
  exit 1
fi

# Must have rules for /service-a → svc-a and /service-b → svc-b
CHECK=$(echo "$ROUTE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
found_a=False; found_b=False
for rule in d['spec'].get('rules',[]):
    for m in rule.get('matches',[]):
        p=m.get('path',{}).get('value','')
        backends=[b.get('name','') for b in rule.get('backendRefs',[])]
        if p=='/service-a' and 'svc-a' in backends: found_a=True
        if p=='/service-b' and 'svc-b' in backends: found_b=True
print('ok' if found_a and found_b else 'missing')
")
if [[ "$CHECK" != "ok" ]]; then
  echo "FAIL: HTTPRoute does not have correct rules for /service-a→svc-a and /service-b→svc-b"
  exit 1
fi

if [[ ! -f /opt/cka/app-route.yaml ]]; then
  echo "FAIL: /opt/cka/app-route.yaml not saved"
  exit 1
fi

echo "PASS: Gateway main-gateway and HTTPRoute app-route correctly configured; YAML saved"
