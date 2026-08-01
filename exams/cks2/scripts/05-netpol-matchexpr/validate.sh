#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NP=$(kubectl get networkpolicy backend-allow-tier -n netpol-expressions -o json 2>/dev/null) || {
  echo "FAIL: NetworkPolicy backend-allow-tier not found in netpol-expressions"
  exit 1
}

PS=$(echo "$NP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spec']['podSelector'].get('matchLabels',{}).get('app',''))")
if [[ "$PS" != "backend" ]]; then
  echo "FAIL: podSelector does not target app=backend (got: $PS)"
  exit 1
fi

FOUND=$(echo "$NP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for rule in d['spec'].get('ingress',[]):
    ports=[p.get('port') for p in rule.get('ports',[])]
    if 8080 not in ports:
        continue
    for peer in rule.get('from',[]):
        exprs=peer.get('podSelector',{}).get('matchExpressions',[])
        for e in exprs:
            if e.get('key')=='tier' and e.get('operator')=='In':
                vals=sorted(e.get('values',[]))
                if 'api' in vals and 'frontend' in vals:
                    print('ok'); sys.exit(0)
print('missing')
")
if [[ "$FOUND" != "ok" ]]; then
  echo "FAIL: no ingress rule on port 8080 with matchExpressions tier In [frontend, api]"
  exit 1
fi

echo "PASS: backend-allow-tier allows ingress:8080 from tier In [frontend,api] via matchExpressions"
