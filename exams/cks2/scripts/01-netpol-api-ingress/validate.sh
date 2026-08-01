#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NP=$(kubectl get networkpolicy api-ingress -n netpol-cross -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy api-ingress not found in namespace netpol-cross"
  exit 1
}

# Check podSelector targets app=api
PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('app',''))")
if [[ "$PS" != "api" ]]; then
  echo "FAIL: podSelector does not target app=api (got: $PS)"
  exit 1
fi

# Must have at least 2 ingress rules
RULE_COUNT=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['spec'].get('ingress',[])))")
if (( RULE_COUNT < 2 )); then
  echo "FAIL: expected at least 2 ingress rules, found $RULE_COUNT"
  exit 1
fi

# Check port 8081 rule has podSelector role=frontend
FOUND_8081=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 8081 in ports:
        for peer in rule.get('from', []):
            ps = peer.get('podSelector', {}).get('matchLabels', {})
            if ps.get('role') == 'frontend':
                print('ok')
                sys.exit(0)
print('missing')
")
if [[ "$FOUND_8081" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 8081 from podSelector role=frontend"
  exit 1
fi

# Check port 8443 rule has namespaceSelector team=ops
FOUND_8443=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 8443 in ports:
        for peer in rule.get('from', []):
            ns = peer.get('namespaceSelector', {}).get('matchLabels', {})
            if ns.get('team') == 'ops':
                print('ok')
                sys.exit(0)
print('missing')
")
if [[ "$FOUND_8443" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 8443 from namespaceSelector team=ops"
  exit 1
fi

echo "PASS: api-ingress NetworkPolicy correctly allows frontend:8081 and ops-namespace:8443 to app=api pods"
