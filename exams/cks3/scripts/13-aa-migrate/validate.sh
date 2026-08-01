#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! aa-status 2>/dev/null | grep -q "k8s-deny-proc"; then
  echo "FAIL: AppArmor profile k8s-deny-proc is not loaded"
  exit 1
fi

POD=$(kubectl get pod legacy-secure -n apparmor-migrate -o json 2>/dev/null) || {
  echo "FAIL: pod legacy-secure not found in namespace apparmor-migrate"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod legacy-secure is not Running (phase: $PHASE)"
  exit 1
fi

NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "controlplane" ]]; then
  echo "FAIL: pod legacy-secure is not on controlplane (nodeName: $NODE)"
  exit 1
fi

AA_ANNOTATION=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
anns=d['metadata'].get('annotations',{})
for k,v in anns.items():
    if 'apparmor' in k.lower() and 'k8s-deny-proc' in v:
        print('ok'); sys.exit(0)
print('missing')
")
AA_NATIVE=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
sc=spec.get('securityContext',{})
if sc.get('appArmorProfile',{}).get('localhostProfile','')=='k8s-deny-proc':
    print('ok'); sys.exit(0)
for c in spec.get('containers',[]):
    if c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile','')=='k8s-deny-proc':
        print('ok'); sys.exit(0)
print('missing')
" 2>/dev/null || echo "missing")

if [[ "$AA_ANNOTATION" != "ok" && "$AA_NATIVE" != "ok" ]]; then
  echo "FAIL: pod legacy-secure does not have AppArmor profile k8s-deny-proc applied"
  exit 1
fi

if [[ ! -f /opt/cks3-apparmor/legacy-secure.yaml ]]; then
  echo "FAIL: /opt/cks3-apparmor/legacy-secure.yaml not saved"
  exit 1
fi

echo "PASS: pod legacy-secure running on controlplane with profile k8s-deny-proc; YAML saved"
