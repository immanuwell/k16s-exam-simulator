#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check profile is loaded
if ! aa-status 2>/dev/null | grep -q "k8s-allow-tmp"; then
  echo "FAIL: AppArmor profile k8s-allow-tmp is not loaded (run apparmor_parser -r -W /etc/apparmor.d/k8s-allow-tmp)"
  exit 1
fi

# Check pod exists and is running
POD=$(kubectl get pod tmp-writer -n apparmor-2 -o json 2>/dev/null) || {
  echo "FAIL: pod tmp-writer not found in namespace apparmor-2"
  exit 1
}
PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod tmp-writer is not Running (phase: $PHASE)"
  exit 1
fi

# Check AppArmor applied — accept both annotation and native style
AA_ANNOTATION=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
anns=d['metadata'].get('annotations',{})
for k,v in anns.items():
    if 'apparmor' in k.lower() and 'k8s-allow-tmp' in v:
        print('ok'); sys.exit(0)
print('missing')
")
AA_NATIVE=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
spec=d['spec']
# pod-level
sc=spec.get('securityContext',{})
if sc.get('appArmorProfile',{}).get('localhostProfile','')=='k8s-allow-tmp':
    print('ok'); sys.exit(0)
# container-level
for c in spec.get('containers',[]):
    if c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile','')=='k8s-allow-tmp':
        print('ok'); sys.exit(0)
print('missing')
" 2>/dev/null || echo "missing")

if [[ "$AA_ANNOTATION" != "ok" && "$AA_NATIVE" != "ok" ]]; then
  echo "FAIL: pod tmp-writer does not have AppArmor profile k8s-allow-tmp applied"
  exit 1
fi

# Check nodeName
NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "controlplane" ]]; then
  echo "FAIL: pod tmp-writer is not scheduled to controlplane (nodeName: $NODE)"
  exit 1
fi

# Check manifest saved
if [[ ! -f /opt/cks2-apparmor/tmp-writer.yaml ]]; then
  echo "FAIL: /opt/cks2-apparmor/tmp-writer.yaml not found"
  exit 1
fi

echo "PASS: AppArmor profile k8s-allow-tmp loaded; pod tmp-writer running on controlplane with profile applied"
