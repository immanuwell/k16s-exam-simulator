#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NP=$(kubectl get networkpolicy proxy-lockdown -n netpol-proxy -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy proxy-lockdown not found in netpol-proxy"
  exit 1
}

PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('app',''))")
if [[ "$PS" != "proxy" ]]; then
  echo "FAIL: podSelector does not target app=proxy (got: $PS)"
  exit 1
fi

TYPES=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(sorted(d['spec'].get('policyTypes',[]))))")
if [[ "$TYPES" != "Egress,Ingress" ]]; then
  echo "FAIL: policyTypes should be [Ingress, Egress], got: $TYPES"
  exit 1
fi

FOUND_INGRESS=$(echo "$NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('ingress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 3128 in ports:
        for peer in rule.get('from',[]):
            ns=peer.get('namespaceSelector',{}).get('matchLabels',{})
            if ns.get('team')=='edge':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_INGRESS" != "ok" ]]; then
  echo "FAIL: no ingress rule allows TCP 3128 from namespaceSelector team=edge"
  exit 1
fi

FOUND_EGRESS=$(echo "$NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 443 in ports:
        for peer in rule.get('to',[]):
            cidr=peer.get('ipBlock',{}).get('cidr','')
            if '10.20.0.0/16' in cidr:
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_EGRESS" != "ok" ]]; then
  echo "FAIL: no egress rule allows TCP 443 to CIDR 10.20.0.0/16"
  exit 1
fi

echo "PASS: proxy-lockdown correctly restricts ingress to team=edge:3128 and egress to 10.20.0.0/16:443"
