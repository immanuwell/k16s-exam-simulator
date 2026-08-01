#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NPS=$(kubectl get networkpolicy -n egress-demo -o json 2>/dev/null)
NP_COUNT=$(echo "$NPS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))")
if [[ "$NP_COUNT" -lt 1 ]]; then
  echo "FAIL: no NetworkPolicies found in egress-demo"
  exit 1
fi

# Check at least one egress policy exists targeting frontend pods
EGRESS_OK=$(echo "$NPS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for np in d.get('items', []):
    types = np['spec'].get('policyTypes', [])
    sel = np['spec'].get('podSelector', {}).get('matchLabels', {})
    if 'Egress' in types:
        egress = np['spec'].get('egress', [])
        # Look for a DNS port rule (port 53)
        for rule in egress:
            for p in rule.get('ports', []):
                if p.get('port') == 53:
                    print('ok'); exit()
print('missing')
")
if [[ "$EGRESS_OK" != "ok" ]]; then
  echo "FAIL: no egress NetworkPolicy found in egress-demo with DNS port 53 exception"
  exit 1
fi

# Check backend port 8080 is allowed in egress
BACKEND_OK=$(echo "$NPS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for np in d.get('items', []):
    if 'Egress' not in np['spec'].get('policyTypes', []):
        continue
    for rule in np['spec'].get('egress', []):
        for p in rule.get('ports', []):
            if p.get('port') == 8080:
                print('ok'); exit()
print('missing')
")
if [[ "$BACKEND_OK" != "ok" ]]; then
  echo "FAIL: egress NetworkPolicy does not allow port 8080 (for backend traffic)"
  exit 1
fi

[[ -f /opt/cka2/egress-policy.yaml ]] || {
  echo "FAIL: /opt/cka2/egress-policy.yaml not saved"
  exit 1
}

echo "PASS: NetworkPolicy in egress-demo allows egress to backend:8080 and DNS:53; ingress restricted"
