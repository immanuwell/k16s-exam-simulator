#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD=$(kubectl get pod multi-aa -n apparmor-multi -o json 2>/dev/null) || {
  echo "FAIL: pod multi-aa not found in namespace apparmor-multi"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod multi-aa is not Running (phase: $PHASE)"
  exit 1
fi

NODE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('nodeName',''))")
if [[ "$NODE" != "controlplane" ]]; then
  echo "FAIL: pod multi-aa is not on controlplane (nodeName: $NODE)"
  exit 1
fi

CTR_COUNT=$(echo "$POD" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['spec']['containers']))")
if [[ "$CTR_COUNT" -lt 2 ]]; then
  echo "FAIL: pod multi-aa should have 2 containers (found: $CTR_COUNT)"
  exit 1
fi

check_profile() {
  local ctr="$1"
  local profile="$2"
  echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ctr_name='$ctr'
profile='$profile'
# Check annotation
for k,v in d['metadata'].get('annotations',{}).items():
    if ctr_name in k and 'apparmor' in k.lower() and profile in v:
        print('ok'); sys.exit(0)
# Check native per-container
for c in d['spec'].get('containers',[]):
    if c['name']==ctr_name:
        lp=c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile','')
        if lp==profile:
            print('ok'); sys.exit(0)
print('missing')
"
}

C1=$(check_profile c1 k8s-readonly)
if [[ "$C1" != "ok" ]]; then
  echo "FAIL: container c1 does not have AppArmor profile k8s-readonly"
  exit 1
fi

C2=$(check_profile c2 k8s-tmpwrite)
if [[ "$C2" != "ok" ]]; then
  echo "FAIL: container c2 does not have AppArmor profile k8s-tmpwrite"
  exit 1
fi

if [[ ! -f /opt/cks2-apparmor/multi-aa.yaml ]]; then
  echo "FAIL: /opt/cks2-apparmor/multi-aa.yaml not found"
  exit 1
fi

echo "PASS: pod multi-aa has c1:k8s-readonly and c2:k8s-tmpwrite; running on controlplane"
