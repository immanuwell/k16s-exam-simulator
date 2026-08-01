#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get networkpolicy deny-all-egress -n netpol-external -o json >/dev/null 2>&1 || {
  echo "FAIL: NetworkPolicy deny-all-egress not found in namespace netpol-external"
  exit 1
}

NP=$(kubectl get networkpolicy allow-external-https -n netpol-external -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy allow-external-https not found in namespace netpol-external"
  exit 1
}

FOUND_HTTPS=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('egress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 443 not in ports: continue
    for peer in rule.get('to', []):
        ib = peer.get('ipBlock', {})
        if ib.get('cidr') == '0.0.0.0/0':
            excepts = ib.get('except', [])
            if '169.254.169.254/32' in excepts and '10.10.0.0/16' in excepts:
                print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_HTTPS" != "ok" ]]; then
  echo "FAIL: no egress rule for TCP 443 to 0.0.0.0/0 with except 169.254.169.254/32 and 10.10.0.0/16"
  exit 1
fi

FOUND_DNS=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('egress', []):
    for p in rule.get('ports', []):
        if p.get('port') == 53 and p.get('protocol', 'TCP') == 'UDP':
            print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND_DNS" != "ok" ]]; then
  echo "FAIL: no egress rule for UDP port 53 (DNS)"
  exit 1
fi

if [[ ! -f /opt/cks3-netpol/allow-external-https.yaml ]]; then
  echo "FAIL: /opt/cks3-netpol/allow-external-https.yaml not saved"
  exit 1
fi

echo "PASS: deny-all-egress in place; allow-external-https permits TCP 443 (0.0.0.0/0 except metadata) and DNS UDP 53"
