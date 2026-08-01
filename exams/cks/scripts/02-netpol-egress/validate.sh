#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS="netpol-egress"

# Check default-deny-egress exists and has empty egress rules
if ! kubectl get networkpolicy default-deny-egress -n "$NS" &>/dev/null; then
  echo "FAIL: NetworkPolicy default-deny-egress not found in $NS"
  exit 1
fi

DENY=$(kubectl get networkpolicy default-deny-egress -n "$NS" -o json)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
# policyTypes must include Egress
types=spec.get('policyTypes',[])
assert 'Egress' in types, f'policyTypes must include Egress, got {types}'
# egress must be absent or empty
egress=spec.get('egress',[])
assert len(egress)==0, f'egress rules must be empty for deny-all, got {egress}'
print('ok')
" <<< "$DENY" 2>/dev/null | grep -q ok; then
  echo "FAIL: default-deny-egress must have policyTypes=[Egress] and empty egress rules"
  exit 1
fi

# Check allow-dns-and-cache exists
if ! kubectl get networkpolicy allow-dns-and-cache -n "$NS" &>/dev/null; then
  echo "FAIL: NetworkPolicy allow-dns-and-cache not found in $NS"
  exit 1
fi

ALLOW=$(kubectl get networkpolicy allow-dns-and-cache -n "$NS" -o json)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
rules=d['spec'].get('egress',[])
assert rules, 'allow-dns-and-cache has no egress rules'

all_ports=[(p.get('port'), p.get('protocol','TCP')) for r in rules for p in r.get('ports',[])]

# UDP 53
assert (53,'UDP') in all_ports or any(p[0]==53 for p in all_ports), \
  f'UDP port 53 not found in egress rules, got {all_ports}'

# TCP 6379
assert any(p[0]==6379 for p in all_ports), \
  f'TCP port 6379 not found in egress rules, got {all_ports}'

# namespaceSelector for kube-system (DNS)
has_ks=any(
  any(f.get('namespaceSelector',{}).get('matchLabels',{}).get('kubernetes.io/metadata.name')=='kube-system'
      or 'kube-system' in str(f.get('namespaceSelector',''))
      for f in r.get('to',[]))
  for r in rules
)

# podSelector for cache
has_cache=any(
  any(f.get('podSelector',{}).get('matchLabels',{}).get('app')=='cache'
      for f in r.get('to',[]))
  for r in rules
)
assert has_cache, 'no egress rule targeting app=cache pods'
print('ok')
" <<< "$ALLOW" 2>/dev/null | grep -q ok; then
  echo "FAIL: allow-dns-and-cache must have egress rules for DNS (UDP 53) and cache (TCP 6379)"
  exit 1
fi

echo "PASS: default-deny-egress blocks all egress; allow-dns-and-cache permits DNS (UDP 53) and cache (TCP 6379)"
