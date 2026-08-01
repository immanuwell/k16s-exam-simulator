#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check deny-egress-all
kubectl get networkpolicy deny-egress-all -n netpol-db-egress -o json >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy deny-egress-all not found in netpol-db-egress"
  exit 1
}
DENY_NP=$(kubectl get networkpolicy deny-egress-all -n netpol-db-egress -o json)
HAS_EGRESS_TYPE=$(echo "$DENY_NP" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print('yes' if 'Egress' in d['spec'].get('policyTypes',[]) else 'no')
")
if [[ "$HAS_EGRESS_TYPE" != "yes" ]]; then
  echo "FAIL: deny-egress-all does not have policyTypes Egress"
  exit 1
fi

# Check backend-egress-db
kubectl get networkpolicy backend-egress-db -n netpol-db-egress -o json >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy backend-egress-db not found in netpol-db-egress"
  exit 1
}
DB_NP=$(kubectl get networkpolicy backend-egress-db -n netpol-db-egress -o json)
FOUND_DB=$(echo "$DB_NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 5432 in ports:
        for peer in rule.get('to',[]):
            ns=peer.get('namespaceSelector',{}).get('matchLabels',{})
            ps=peer.get('podSelector',{}).get('matchLabels',{})
            if ns.get('tier')=='database' and ps.get('app')=='db':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_DB" != "ok" ]]; then
  echo "FAIL: backend-egress-db does not allow egress to app=db in tier=database namespace on port 5432"
  exit 1
fi

# Check allow-dns
kubectl get networkpolicy allow-dns -n netpol-db-egress -o json >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy allow-dns not found in netpol-db-egress"
  exit 1
}
DNS_NP=$(kubectl get networkpolicy allow-dns -n netpol-db-egress -o json)
FOUND_DNS=$(echo "$DNS_NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 53 in ports:
        print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_DNS" != "ok" ]]; then
  echo "FAIL: allow-dns does not permit egress on port 53"
  exit 1
fi

echo "PASS: deny-egress-all, backend-egress-db (5432 to tier=database), and allow-dns (port 53) all correct"
