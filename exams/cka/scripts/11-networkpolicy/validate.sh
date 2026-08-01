#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get networkpolicy default-deny-ingress -n netpol-app >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy default-deny-ingress not found in netpol-app"
  exit 1
}

NP=$(kubectl get networkpolicy backend-restrict -n netpol-app -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy backend-restrict not found in netpol-app"
  exit 1
}

# Must target tier=backend
PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('tier',''))")
if [[ "$PS" != "backend" ]]; then
  echo "FAIL: backend-restrict podSelector does not target tier=backend (got: $PS)"
  exit 1
fi

# Must have ingress rule for port 8080 from tier=frontend
FOUND=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 8080 not in ports: continue
    for peer in rule.get('from', []):
        ps = peer.get('podSelector', {}).get('matchLabels', {})
        if ps.get('tier') == 'frontend':
            print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 8080 from tier=frontend"
  exit 1
fi

if [[ ! -f /opt/cka/backend-restrict.yaml ]]; then
  echo "FAIL: /opt/cka/backend-restrict.yaml not saved"
  exit 1
fi

echo "PASS: default-deny-ingress and backend-restrict policies correct; YAML saved"
