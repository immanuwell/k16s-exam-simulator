#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! aa-status 2>/dev/null | grep -q "k8s-read-hosts"; then
  echo "FAIL: AppArmor profile k8s-read-hosts is not loaded"
  exit 1
fi

POD=$(kubectl get pod hosts-check -n apparmor-hosts -o json 2>/dev/null) || {
  echo "FAIL: pod hosts-check not found in namespace apparmor-hosts"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod hosts-check is not Running (phase: $PHASE)"
  exit 1
fi

NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "controlplane" ]]; then
  echo "FAIL: pod hosts-check is not on controlplane (nodeName: $NODE)"
  exit 1
fi

AA_ANNOTATION=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for k,v in d['metadata'].get('annotations',{}).items():
    if 'apparmor' in k.lower() and 'k8s-read-hosts' in v:
        print('ok'); sys.exit(0)
print('missing')
")
AA_NATIVE=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    if c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile','')=='k8s-read-hosts':
        print('ok'); sys.exit(0)
sc=d['spec'].get('securityContext',{})
if sc.get('appArmorProfile',{}).get('localhostProfile','')=='k8s-read-hosts':
    print('ok'); sys.exit(0)
print('missing')
" 2>/dev/null || echo "missing")

if [[ "$AA_ANNOTATION" != "ok" && "$AA_NATIVE" != "ok" ]]; then
  echo "FAIL: pod hosts-check does not have AppArmor profile k8s-read-hosts applied"
  exit 1
fi

if [[ ! -f /opt/cks2-apparmor/hosts-check.yaml ]]; then
  echo "FAIL: /opt/cks2-apparmor/hosts-check.yaml not found"
  exit 1
fi

echo "PASS: AppArmor profile k8s-read-hosts loaded; pod hosts-check running on controlplane with profile applied"
