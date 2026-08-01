#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

ING=$(kubectl get ingress app-ingress -n ingress-demo -o json 2>/dev/null) || {
  echo "FAIL: Ingress app-ingress not found in ingress-demo"
  exit 1
}

CHECK=$(echo "$ING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
rules=d['spec'].get('rules',[])
found_web=False; found_api=False
for rule in rules:
    if rule.get('host') != 'exam.local': continue
    for path in rule.get('http',{}).get('paths',[]):
        p=path.get('path','')
        svc=path.get('backend',{}).get('service',{})
        name=svc.get('name','')
        port=svc.get('port',{}).get('number',0)
        pt=path.get('pathType','')
        if p=='/web' and name=='web-svc' and port==80 and pt=='Prefix': found_web=True
        if p=='/api' and name=='api-svc' and port==8080 and pt=='Prefix': found_api=True
issues=[]
if not found_web: issues.append('missing /web→web-svc:80 with pathType=Prefix')
if not found_api: issues.append('missing /api→api-svc:8080 with pathType=Prefix')
print('|'.join(issues) if issues else 'ok')
")

if [[ "$CHECK" != "ok" ]]; then
  echo "FAIL: Ingress spec is incorrect — $CHECK"
  exit 1
fi

if [[ ! -f /opt/cka/app-ingress.yaml ]]; then
  echo "FAIL: /opt/cka/app-ingress.yaml not saved"
  exit 1
fi

echo "PASS: Ingress app-ingress has correct path rules (exam.local/web→web-svc:80, /api→api-svc:8080)"
