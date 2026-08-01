#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NP=$(kubectl get networkpolicy collector-lockdown -n netpol-logs -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy collector-lockdown not found in netpol-logs"
  exit 1
}

PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('app',''))")
if [[ "$PS" != "collector" ]]; then
  echo "FAIL: podSelector does not target app=collector (got: $PS)"
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
    if 5000 in ports:
        for peer in rule.get('from',[]):
            if peer.get('podSelector',{}).get('matchLabels',{}).get('role')=='shipper':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_INGRESS" != "ok" ]]; then
  echo "FAIL: no ingress rule allows TCP 5000 from role=shipper"
  exit 1
fi

FOUND_EGRESS=$(echo "$NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    has_5044=5044 in ports
    has_9200=9200 in ports
    if has_5044 or has_9200:
        for peer in rule.get('to',[]):
            ns=peer.get('namespaceSelector',{}).get('matchLabels',{})
            if ns.get('purpose')=='logging':
                if has_5044 and has_9200:
                    print('ok'); sys.exit(0)
                elif has_5044:
                    print('5044only')
                    sys.exit(0)
                else:
                    print('9200only')
                    sys.exit(0)
print('missing')
")
if [[ "$FOUND_EGRESS" == "5044only" ]]; then
  echo "FAIL: egress to purpose=logging only covers port 5044; also need 9200"
  exit 1
elif [[ "$FOUND_EGRESS" == "9200only" ]]; then
  echo "FAIL: egress to purpose=logging only covers port 9200; also need 5044"
  exit 1
elif [[ "$FOUND_EGRESS" != "ok" ]]; then
  echo "FAIL: no egress rule allows TCP 5044 and 9200 to namespaceSelector purpose=logging"
  exit 1
fi

echo "PASS: collector-lockdown allows shipper:5000 ingress and logging-ns:5044+9200 egress"
