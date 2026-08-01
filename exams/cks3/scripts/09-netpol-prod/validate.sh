#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS_LABEL=$(kubectl get namespace prod-apps -o jsonpath='{.metadata.labels.env}' 2>/dev/null)
if [[ "$NS_LABEL" != "prod" ]]; then
  echo "FAIL: namespace prod-apps does not have label env=prod (got: '$NS_LABEL')"
  exit 1
fi

NP=$(kubectl get networkpolicy payments-ingress-prod -n netpol-prod -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy payments-ingress-prod not found in namespace netpol-prod"
  exit 1
}

PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('app',''))")
if [[ "$PS" != "payments" ]]; then
  echo "FAIL: podSelector does not target app=payments (got: $PS)"
  exit 1
fi

FOUND=$(echo "$NP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rule in d['spec'].get('ingress', []):
    ports = [p.get('port') for p in rule.get('ports', [])]
    if 9443 not in ports:
        continue
    for peer in rule.get('from', []):
        ns = peer.get('namespaceSelector', {}).get('matchLabels', {})
        ps = peer.get('podSelector', {}).get('matchLabels', {})
        if ns.get('env') == 'prod' and ps.get('access') == 'allowed':
            print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND" != "ok" ]]; then
  echo "FAIL: no ingress rule allows port 9443 from pods access=allowed in namespaces env=prod"
  exit 1
fi

if [[ ! -f /opt/cks3-netpol/payments-ingress-prod.yaml ]]; then
  echo "FAIL: /opt/cks3-netpol/payments-ingress-prod.yaml not saved"
  exit 1
fi

echo "PASS: prod-apps labelled; payments-ingress-prod allows port 9443 from access=allowed in env=prod namespaces only"
