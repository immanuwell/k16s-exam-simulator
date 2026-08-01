#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD="hardened"
PROFILE="k8s-no-proc-write"
CTR="app"

STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$STATUS" != "Running" ]]; then
  echo "FAIL: pod $POD is not Running (status: ${STATUS:-not found})"
  exit 1
fi

POD_JSON=$(kubectl get pod "$POD" -o json)

# Check seccomp RuntimeDefault at pod level
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
sc=d.get('spec',{}).get('securityContext',{})
sp=sc.get('seccompProfile',{})
assert sp.get('type')=='RuntimeDefault', \
  f'pod-level seccompProfile.type must be RuntimeDefault, got {sp}'
print('ok')
" <<< "$POD_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: pod $POD does not have seccompProfile.type=RuntimeDefault at pod level"
  exit 1
fi

# Check AppArmor profile (annotation OR native field)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
profile='$PROFILE'
ctr_name='$CTR'

ann=d.get('metadata',{}).get('annotations',{})
key='container.apparmor.security.beta.kubernetes.io/'+ctr_name
ann_match=(ann.get(key)=='localhost/'+profile)

ctrs=d.get('spec',{}).get('containers',[])
native_match=any(
  c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile')==profile
  for c in ctrs
)
pod_sc=d.get('spec',{}).get('securityContext',{})
pod_native=(pod_sc.get('appArmorProfile',{}).get('localhostProfile')==profile)

assert ann_match or native_match or pod_native, \
  f'AppArmor profile {profile} not found on container {ctr_name}'
print('ok')
" <<< "$POD_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: pod $POD does not have AppArmor profile $PROFILE on container $CTR"
  exit 1
fi

if [[ ! -f /opt/cks-security/hardened.yaml ]]; then
  echo "FAIL: pod manifest not saved to /opt/cks-security/hardened.yaml"
  exit 1
fi

echo "PASS: pod hardened is running with AppArmor k8s-no-proc-write and seccomp RuntimeDefault"
