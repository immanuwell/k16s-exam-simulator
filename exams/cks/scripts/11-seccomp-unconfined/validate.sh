#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NS="seccomp-fix"

# The original unconfined-pod must be gone OR replaced with RuntimeDefault
# Accept: pod gone + new pod exists with RuntimeDefault, OR same pod name with RuntimeDefault
POD_JSON=$(kubectl get pod unconfined-pod -n "$NS" -o json 2>/dev/null || echo "")

if [[ -z "$POD_JSON" ]]; then
  echo "FAIL: no pod named unconfined-pod found in $NS — recreate it with RuntimeDefault seccomp"
  exit 1
fi

# Check that the pod now has RuntimeDefault (not Unconfined)
if ! python3 -c "
import sys,json
d=json.loads('''$(echo "$POD_JSON" | python3 -c "import sys; print(sys.stdin.read().replace(\"'\",\"\\\\'\"))")''')
" 2>/dev/null; then
  # Fallback: use jsonpath
  TYPE=$(kubectl get pod unconfined-pod -n "$NS" \
    -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
  if [[ "$TYPE" != "RuntimeDefault" ]]; then
    echo "FAIL: pod unconfined-pod has seccompProfile.type='${TYPE:-unset}', expected RuntimeDefault"
    exit 1
  fi
else
  TYPE=$(kubectl get pod unconfined-pod -n "$NS" \
    -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
  if [[ "$TYPE" == "Unconfined" ]]; then
    echo "FAIL: pod unconfined-pod still uses Unconfined seccomp — delete and recreate with RuntimeDefault"
    exit 1
  fi
  if [[ "$TYPE" != "RuntimeDefault" ]]; then
    echo "FAIL: pod unconfined-pod has seccompProfile.type='${TYPE:-unset}', expected RuntimeDefault"
    exit 1
  fi
fi

STATUS=$(kubectl get pod unconfined-pod -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$STATUS" != "Running" ]]; then
  echo "FAIL: pod unconfined-pod is not Running (status: ${STATUS:-unknown})"
  exit 1
fi

if [[ ! -f /opt/cks-seccomp/fixed-pod.yaml ]]; then
  echo "FAIL: fixed pod manifest not saved to /opt/cks-seccomp/fixed-pod.yaml"
  exit 1
fi

echo "PASS: pod unconfined-pod replaced with RuntimeDefault seccomp in namespace seccomp-fix"
