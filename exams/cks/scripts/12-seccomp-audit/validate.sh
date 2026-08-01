#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PROFILE_PATH="/var/lib/kubelet/seccomp/profiles/audit-write.json"
COPY_PATH="/opt/cks-seccomp/audit-write.json"
POD="audit-write"

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "FAIL: seccomp profile not found at $PROFILE_PATH"
  exit 1
fi

if ! python3 -c "
import json
with open('$PROFILE_PATH') as f:
  d=json.load(f)
assert d.get('defaultAction')=='SCMP_ACT_ALLOW', \
  f'defaultAction must be SCMP_ACT_ALLOW, got {d.get(\"defaultAction\")}'
syscalls=d.get('syscalls',[])
assert syscalls, 'syscalls array is empty'
logged=set()
for s in syscalls:
  if s.get('action')=='SCMP_ACT_LOG':
    logged.update(s.get('names',[]))
assert 'write' in logged, f'write not in SCMP_ACT_LOG syscalls, got {logged}'
assert 'writev' in logged, f'writev not in SCMP_ACT_LOG syscalls, got {logged}'
print('ok')
" 2>/dev/null | grep -q ok; then
  echo "FAIL: $PROFILE_PATH must have defaultAction=SCMP_ACT_ALLOW and SCMP_ACT_LOG for write+writev"
  exit 1
fi

STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$STATUS" != "Running" ]]; then
  echo "FAIL: pod $POD is not Running (status: ${STATUS:-not found})"
  exit 1
fi

POD_JSON=$(kubectl get pod "$POD" -o json)
if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
pod_sc=d.get('spec',{}).get('securityContext',{})
pod_sp=pod_sc.get('seccompProfile',{})
ctrs=d.get('spec',{}).get('containers',[])
ctr_sp=next((c.get('securityContext',{}).get('seccompProfile',{}) for c in ctrs), {})
for sp in [pod_sp, ctr_sp]:
  if sp.get('type')=='Localhost' and 'audit-write' in sp.get('localhostProfile',''):
    print('ok')
    sys.exit(0)
sys.exit(1)
" <<< "$POD_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: pod $POD does not use Localhost seccomp profile profiles/audit-write.json"
  exit 1
fi

if [[ ! -f "$COPY_PATH" ]]; then
  echo "FAIL: profile not copied to $COPY_PATH"
  exit 1
fi

echo "PASS: audit-write.json seccomp profile logs write+writev; pod audit-write is running with it"
