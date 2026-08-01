#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PROFILE_PATH="/var/lib/kubelet/seccomp/profiles/block-mkdir.json"
COPY_PATH="/opt/cks-seccomp/block-mkdir.json"
POD="seccomp-mkdir"

# Check profile file exists
if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "FAIL: seccomp profile not found at $PROFILE_PATH"
  exit 1
fi

# Validate profile content
if ! python3 -c "
import json,sys
with open('$PROFILE_PATH') as f:
  d=json.load(f)
assert d.get('defaultAction')=='SCMP_ACT_ALLOW', \
  f'defaultAction must be SCMP_ACT_ALLOW, got {d.get(\"defaultAction\")}'
syscalls=d.get('syscalls',[])
assert syscalls, 'syscalls array is empty'
blocked=set()
for s in syscalls:
  if s.get('action')=='SCMP_ACT_ERRNO':
    blocked.update(s.get('names',[]))
assert 'mkdir' in blocked, f'mkdir not in SCMP_ACT_ERRNO syscalls, got {blocked}'
assert 'mkdirat' in blocked, f'mkdirat not in SCMP_ACT_ERRNO syscalls, got {blocked}'
print('ok')
" 2>/dev/null | grep -q ok; then
  echo "FAIL: $PROFILE_PATH has incorrect content — need defaultAction=SCMP_ACT_ALLOW and SCMP_ACT_ERRNO for mkdir+mkdirat"
  exit 1
fi

# Check pod is Running
STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$STATUS" != "Running" ]]; then
  echo "FAIL: pod $POD is not Running (status: ${STATUS:-not found})"
  exit 1
fi

# Check pod has Localhost seccomp with this profile
POD_JSON=$(kubectl get pod "$POD" -o json)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)

# Check at pod level
pod_sc=d.get('spec',{}).get('securityContext',{})
pod_sp=pod_sc.get('seccompProfile',{})

# Check at container level
ctrs=d.get('spec',{}).get('containers',[])
ctr_sp=next((c.get('securityContext',{}).get('seccompProfile',{}) for c in ctrs), {})

for sp in [pod_sp, ctr_sp]:
  if sp.get('type')=='Localhost' and 'block-mkdir' in sp.get('localhostProfile',''):
    print('ok')
    sys.exit(0)

sys.exit(1)
" <<< "$POD_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: pod $POD does not use Localhost seccomp profile profiles/block-mkdir.json"
  exit 1
fi

# Check copy
if [[ ! -f "$COPY_PATH" ]]; then
  echo "FAIL: profile not copied to $COPY_PATH"
  exit 1
fi

echo "PASS: block-mkdir.json seccomp profile is correct and applied to pod seccomp-mkdir"
