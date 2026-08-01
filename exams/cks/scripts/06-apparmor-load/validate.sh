#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PROFILE="k8s-deny-etc"
POD="deny-etc-pod"

# Check profile is loaded
if ! aa-status --json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
profs=d.get('profiles',{})
assert '$PROFILE' in profs, f'profile $PROFILE not found in aa-status; loaded: {list(profs.keys())[:10]}'
print('ok')
" 2>/dev/null | grep -q ok; then
  echo "FAIL: AppArmor profile $PROFILE is not loaded — run: apparmor_parser -r -W /etc/apparmor.d/k8s-deny-etc"
  exit 1
fi

# Check pod is Running
STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$STATUS" != "Running" ]]; then
  echo "FAIL: pod $POD is not Running (status: ${STATUS:-not found})"
  exit 1
fi

# Check AppArmor profile is applied (annotation OR native securityContext)
POD_JSON=$(kubectl get pod "$POD" -o json)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
profile='$PROFILE'

# Check annotation style
ann=d.get('metadata',{}).get('annotations',{})
ann_match=any('localhost/'+profile in v for v in ann.values())

# Check native securityContext style (K8s 1.30+)
ctrs=d.get('spec',{}).get('containers',[])
native_match=any(
  c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile')==profile
  for c in ctrs
)
pod_sc=d.get('spec',{}).get('securityContext',{})
pod_native=pod_sc.get('appArmorProfile',{}).get('localhostProfile')==profile

assert ann_match or native_match or pod_native, \
  f'AppArmor profile {profile} not found in pod annotations or securityContext'
print('ok')
" <<< "$POD_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: pod $POD does not have AppArmor profile $PROFILE applied"
  exit 1
fi

# Check test output file exists and shows permission denied
if [[ ! -f /opt/cks-apparmor/deny-etc-test.txt ]]; then
  echo "FAIL: test output not saved to /opt/cks-apparmor/deny-etc-test.txt"
  exit 1
fi

if ! grep -qi "permission denied\|operation not permitted" /opt/cks-apparmor/deny-etc-test.txt; then
  echo "FAIL: /opt/cks-apparmor/deny-etc-test.txt does not show write was denied (expected 'Permission denied')"
  exit 1
fi

echo "PASS: AppArmor profile k8s-deny-etc loaded and applied to pod deny-etc-pod; /etc writes are blocked"
