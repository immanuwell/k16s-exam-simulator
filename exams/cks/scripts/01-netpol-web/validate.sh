#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POLICY="web-ingress-allow"
NS="netpol-web"

# Check policy exists
if ! kubectl get networkpolicy "$POLICY" -n "$NS" &>/dev/null; then
  echo "FAIL: NetworkPolicy $POLICY not found in namespace $NS"
  exit 1
fi

RESULT=$(kubectl get networkpolicy "$POLICY" -n "$NS" -o json)

check() {
  python3 -c "$1" <<< "$RESULT"
}

# Check podSelector targets app=backend
if ! check "
import sys,json
d=json.load(sys.stdin)
ps=d['spec'].get('podSelector',{}).get('matchLabels',{})
assert ps.get('app')=='backend', f'podSelector not targeting app=backend, got {ps}'
print('ok')
" 2>/dev/null | grep -q ok; then
  echo "FAIL: policy podSelector must target app=backend"
  exit 1
fi

# Check ingress rules: frontend on 8080 AND monitoring ns on 9100
if ! check "
import sys,json
d=json.load(sys.stdin)
rules=d['spec'].get('ingress',[])

# Flatten all ports across all rules
all_ports=[]
for r in rules:
  for p in r.get('ports',[]):
    all_ports.append(p.get('port'))

# Check port 8080 exists
assert 8080 in all_ports, f'port 8080 not found in ingress rules, got {all_ports}'

# Check port 9100 exists
assert 9100 in all_ports, f'port 9100 not found in ingress rules, got {all_ports}'

# Check a rule has podSelector app=frontend
has_frontend=any(
  any(f.get('podSelector',{}).get('matchLabels',{}).get('app')=='frontend'
      for f in r.get('from',[]))
  for r in rules
)
assert has_frontend, 'no ingress rule with podSelector app=frontend'

# Check a rule has namespaceSelector team=monitoring
has_monitoring=any(
  any(f.get('namespaceSelector',{}).get('matchLabels',{}).get('team')=='monitoring'
      for f in r.get('from',[]))
  for r in rules
)
assert has_monitoring, 'no ingress rule with namespaceSelector team=monitoring'

print('ok')
" 2>/dev/null | grep -q ok; then
  echo "FAIL: ingress rules must include app=frontend on port 8080 AND team=monitoring ns on port 9100"
  exit 1
fi

# Check saved YAML file
if [[ ! -f /opt/cks-netpol/web-ingress-allow.yaml ]]; then
  echo "FAIL: manifest not saved to /opt/cks-netpol/web-ingress-allow.yaml"
  exit 1
fi

echo "PASS: NetworkPolicy web-ingress-allow correctly restricts ingress to app=backend (frontend:8080, monitoring:9100)"
