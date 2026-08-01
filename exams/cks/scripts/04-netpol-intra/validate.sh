#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS="netpol-intra"
POLICY="intra-namespace-only"

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
assert ingress, 'no ingress rules found'

# There must be at least one ingress rule with a namespaceSelector that restricts
# to the same namespace. Accept either:
#   matchLabels: {kubernetes.io/metadata.name: netpol-intra}
# or just a namespaceSelector that isn't empty (allowing same-ns via label).
found=False
for r in ingress:
  for peer in r.get('from',[]):
    ns_sel=peer.get('namespaceSelector',{})
    ml=ns_sel.get('matchLabels',{})
    if ml.get('kubernetes.io/metadata.name')=='netpol-intra':
      found=True
    # Also accept if the peer has ONLY a namespaceSelector with any labels
    # that could match the namespace (lenient check)
    if ml and not peer.get('podSelector') and 'netpol-intra' in str(ml):
      found=True

# Fallback: also accept empty podSelector + namespaceSelector matching ns label
for r in ingress:
  for peer in r.get('from',[]):
    ns_sel=peer.get('namespaceSelector')
    if ns_sel is not None and 'netpol-intra' in str(ns_sel):
      found=True

assert found, 'no ingress rule restricting to same namespace via namespaceSelector'
print('ok')
" <<< "$RESULT" 2>/dev/null | grep -q ok; then
  echo "FAIL: intra-namespace-only must use namespaceSelector matching kubernetes.io/metadata.name=netpol-intra"
  exit 1
fi

echo "PASS: intra-namespace-only restricts ingress to pods within the netpol-intra namespace"
