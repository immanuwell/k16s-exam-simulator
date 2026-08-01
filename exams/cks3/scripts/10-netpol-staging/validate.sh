#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS_LABEL=$(kubectl get namespace ops-team -o jsonpath='{.metadata.labels.team}' 2>/dev/null)
if [[ "$NS_LABEL" != "ops" ]]; then
  echo "FAIL: namespace ops-team does not have label team=ops (got: '$NS_LABEL')"
  exit 1
fi

kubectl get networkpolicy deny-ingress-all -n netpol-staging -o json >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy deny-ingress-all not found in namespace netpol-staging"
  exit 1
}

NP=$(kubectl get networkpolicy staging-allowlist -n netpol-staging -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy staging-allowlist not found in namespace netpol-staging"
  exit 1
}

FOUND_8080=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 8080 in ports:
        for peer in rule.get('from', []):
            ns = peer.get('namespaceSelector', {}).get('matchLabels', {})
            if ns.get('team') == 'ops':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_8080" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 8080 from namespaceSelector team=ops"
  exit 1
fi

FOUND_8443=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 8443 in ports:
        for peer in rule.get('from', []):
            ns = peer.get('namespaceSelector', {}).get('matchLabels', {})
            if ns.get('team') == 'ops':
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_8443" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 8443 from namespaceSelector team=ops"
  exit 1
fi

FOUND_CIDR=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 443 in ports:
        for peer in rule.get('from', []):
            cidr = peer.get('ipBlock', {}).get('cidr', '')
            if '198.51.100.0/24' in cidr:
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_CIDR" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 443 from CIDR 198.51.100.0/24"
  exit 1
fi

if [[ ! -f /opt/cks3-netpol/staging-allowlist.yaml ]]; then
  echo "FAIL: /opt/cks3-netpol/staging-allowlist.yaml not saved"
  exit 1
fi

echo "PASS: staging-allowlist allows ops-team ports 8080/8443 and CIDR 198.51.100.0/24 port 443; default-deny in place"
