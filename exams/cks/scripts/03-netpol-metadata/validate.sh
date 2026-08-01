#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS="netpol-metadata"
POLICY="block-metadata"

if ! kubectl get networkpolicy "$POLICY" -n "$NS" &>/dev/null; then
  echo "FAIL: NetworkPolicy $POLICY not found in namespace $NS"
  exit 1
fi

RESULT=$(kubectl get networkpolicy "$POLICY" -n "$NS" -o json)

if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
rules=spec.get('egress',[])
assert rules, 'no egress rules found'

# Find ipBlock rule that has except 169.254.169.254/32
has_block=False
for r in rules:
  for peer in r.get('to',[]):
    ib=peer.get('ipBlock',{})
    if ib.get('cidr')=='0.0.0.0/0':
      exc=ib.get('except',[])
      if '169.254.169.254/32' in exc:
        has_block=True
      break

assert has_block, 'no egress ipBlock rule with cidr=0.0.0.0/0 except=[169.254.169.254/32]'

# policyTypes must include Egress
types=spec.get('policyTypes',[])
assert 'Egress' in types, f'policyTypes must include Egress, got {types}'

print('ok')
" <<< "$RESULT" 2>/dev/null | grep -q ok; then
  echo "FAIL: block-metadata must have egress ipBlock 0.0.0.0/0 with except 169.254.169.254/32"
  exit 1
fi

# Check saved YAML
if [[ ! -f /opt/cks-netpol/block-metadata.yaml ]]; then
  echo "FAIL: manifest not saved to /opt/cks-netpol/block-metadata.yaml"
  exit 1
fi

echo "PASS: block-metadata NetworkPolicy correctly blocks 169.254.169.254/32 (cloud metadata endpoint)"
