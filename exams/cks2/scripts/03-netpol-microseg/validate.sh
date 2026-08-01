#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check deny-all-ingress
DENY_NP=$(kubectl get networkpolicy deny-all-ingress -n netpol-internal -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy deny-all-ingress not found in netpol-internal"
  exit 1
}
HAS_INGRESS_TYPE=$(echo "$DENY_NP" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print('yes' if 'Ingress' in d['spec'].get('policyTypes',[]) else 'no')
")
if [[ "$HAS_INGRESS_TYPE" != "yes" ]]; then
  echo "FAIL: deny-all-ingress missing policyTypes Ingress"
  exit 1
fi
# ingress key should be absent or empty
INGRESS_RULES=$(echo "$DENY_NP" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(len(d['spec'].get('ingress',[])))
")
if [[ "$INGRESS_RULES" != "0" ]]; then
  echo "FAIL: deny-all-ingress should have no ingress rules (found $INGRESS_RULES)"
  exit 1
fi

# Check worker-egress-internal
WORKER_NP=$(kubectl get networkpolicy worker-egress-internal -n netpol-internal -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy worker-egress-internal not found in netpol-internal"
  exit 1
}
WORKER_PS=$(echo "$WORKER_NP" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d['spec']['podSelector'].get('matchLabels',{}).get('role',''))
")
if [[ "$WORKER_PS" != "worker" ]]; then
  echo "FAIL: worker-egress-internal podSelector does not target role=worker"
  exit 1
fi

FOUND_API=$(echo "$WORKER_NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 7000 in ports:
        for peer in rule.get('to',[]):
            if peer.get('podSelector',{}).get('matchLabels',{}).get('role')=='api':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_API" != "ok" ]]; then
  echo "FAIL: no egress rule for role=api on port 7000"
  exit 1
fi

FOUND_METRICS=$(echo "$WORKER_NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('egress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 9100 in ports:
        for peer in rule.get('to',[]):
            if peer.get('podSelector',{}).get('matchLabels',{}).get('role')=='metrics':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_METRICS" != "ok" ]]; then
  echo "FAIL: no egress rule for role=metrics on port 9100"
  exit 1
fi

HAS_EGRESS_TYPE=$(echo "$WORKER_NP" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print('yes' if 'Egress' in d['spec'].get('policyTypes',[]) else 'no')
")
if [[ "$HAS_EGRESS_TYPE" != "yes" ]]; then
  echo "FAIL: worker-egress-internal missing policyTypes Egress"
  exit 1
fi

echo "PASS: deny-all-ingress blocks all ingress; worker-egress-internal allows api:7000 and metrics:9100 from role=worker"
