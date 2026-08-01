#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! aa-status 2>/dev/null | grep -q "k8s-no-proc-write"; then
  echo "FAIL: AppArmor profile k8s-no-proc-write is not loaded"
  exit 1
fi

POD=$(kubectl get pod proc-guard -n apparmor-3 -o json 2>/dev/null) || {
  echo "FAIL: pod proc-guard not found in namespace apparmor-3"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod proc-guard is not Running (phase: $PHASE)"
  exit 1
fi

NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "controlplane" ]]; then
  echo "FAIL: pod proc-guard is not on controlplane (nodeName: $NODE)"
  exit 1
fi

AA_ANNOTATION=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
anns=d['metadata'].get('annotations',{})
for k,v in anns.items():
    if 'apparmor' in k.lower() and 'k8s-no-proc-write' in v:
        print('ok'); sys.exit(0)
print('missing')
")
AA_NATIVE=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
sc=spec.get('securityContext',{})
if sc.get('appArmorProfile',{}).get('localhostProfile','')=='k8s-no-proc-write':
    print('ok'); sys.exit(0)
for c in spec.get('containers',[]):
    if c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile','')=='k8s-no-proc-write':
        print('ok'); sys.exit(0)
print('missing')
" 2>/dev/null || echo "missing")

if [[ "$AA_ANNOTATION" != "ok" && "$AA_NATIVE" != "ok" ]]; then
  echo "FAIL: pod proc-guard does not have AppArmor profile k8s-no-proc-write applied"
  exit 1
fi

if [[ ! -f /opt/cks3-apparmor/proc-guard-annotations.txt ]]; then
  echo "FAIL: /opt/cks3-apparmor/proc-guard-annotations.txt not saved"
  exit 1
fi

if ! grep -q 'apparmor\|k8s-no-proc-write' /opt/cks3-apparmor/proc-guard-annotations.txt; then
  echo "FAIL: proc-guard-annotations.txt does not contain AppArmor annotation content"
  exit 1
fi

echo "PASS: proc-guard running on controlplane with k8s-no-proc-write profile; annotations saved"
