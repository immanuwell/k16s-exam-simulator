#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD=$(kubectl get pod seccomp-override -n seccomp-override -o json 2>/dev/null) || {
  echo "FAIL: pod seccomp-override not found in namespace seccomp-override"
  exit 1
}

# Pod-level seccomp must be RuntimeDefault
POD_SECCOMP=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
sc=d['spec'].get('securityContext',{})
print(sc.get('seccompProfile',{}).get('type',''))
")
if [[ "$POD_SECCOMP" != "RuntimeDefault" ]]; then
  echo "FAIL: pod-level seccompProfile is not RuntimeDefault (got: $POD_SECCOMP)"
  exit 1
fi

# Container-level seccomp must be Localhost with profiles/allow-read.json
CTR_SECCOMP=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec'].get('containers',[]):
    sc=c.get('securityContext',{}).get('seccompProfile',{})
    if sc.get('type')=='Localhost' and sc.get('localhostProfile','')=='profiles/allow-read.json':
        print('ok'); sys.exit(0)
print('missing')
")
if [[ "$CTR_SECCOMP" != "ok" ]]; then
  echo "FAIL: no container has seccompProfile type=Localhost localhostProfile=profiles/allow-read.json"
  exit 1
fi

if [[ ! -f /opt/cks2-seccomp/seccomp-override.yaml ]]; then
  echo "FAIL: /opt/cks2-seccomp/seccomp-override.yaml not found"
  exit 1
fi

echo "PASS: seccomp-override pod has RuntimeDefault at pod level and Localhost profiles/allow-read.json at container level"
