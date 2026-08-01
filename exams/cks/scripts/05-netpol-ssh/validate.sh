#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS="netpol-ssh"
POLICY="allow-ssh-office"

if ! kubectl get networkpolicy "$POLICY" -n "$NS" &>/dev/null; then
  echo "FAIL: NetworkPolicy $POLICY not found in namespace $NS"
  exit 1
fi

RESULT=$(kubectl get networkpolicy "$POLICY" -n "$NS" -o json)

if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
ingress=spec.get('ingress',[])
assert ingress, 'no ingress rules'

# Find a rule with port 22 and the correct ipBlock
found_cidr=False
found_except=False
found_port=False
for r in ingress:
  for peer in r.get('from',[]):
    ib=peer.get('ipBlock',{})
    if ib.get('cidr')=='203.0.113.0/24':
      found_cidr=True
      exc=ib.get('except',[])
      if '203.0.113.128/25' in exc:
        found_except=True
  for p in r.get('ports',[]):
    if p.get('port')==22:
      found_port=True

assert found_cidr,  'ipBlock cidr 203.0.113.0/24 not found'
assert found_except,'except 203.0.113.128/25 not found'
assert found_port,  'port 22 not found in ingress rule'
print('ok')
" <<< "$RESULT" 2>/dev/null | grep -q ok; then
  echo "FAIL: allow-ssh-office must have ingress port 22 from 203.0.113.0/24 except 203.0.113.128/25"
  exit 1
fi

if [[ ! -f /opt/cks-netpol/allow-ssh-office.yaml ]]; then
  echo "FAIL: manifest not saved to /opt/cks-netpol/allow-ssh-office.yaml"
  exit 1
fi

echo "PASS: allow-ssh-office permits TCP 22 from 203.0.113.0/24 (excluding 203.0.113.128/25)"
