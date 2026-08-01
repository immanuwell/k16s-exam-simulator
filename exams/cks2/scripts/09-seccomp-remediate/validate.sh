#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check pod no-seccomp is running with RuntimeDefault
POD=$(kubectl get pod no-seccomp -n seccomp-audit -o json 2>/dev/null) || {
  echo "FAIL: pod no-seccomp not found in namespace seccomp-audit"
  exit 1
}

SECCOMP_TYPE=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d['spec'].get('securityContext',{}).get('seccompProfile',{}).get('type',''))
")
if [[ "$SECCOMP_TYPE" != "RuntimeDefault" ]]; then
  echo "FAIL: pod no-seccomp seccompProfile is not RuntimeDefault (got: $SECCOMP_TYPE)"
  exit 1
fi

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod no-seccomp is not Running (phase: $PHASE)"
  exit 1
fi

# Check audit file exists and is non-empty
if [[ ! -s /opt/cks2-seccomp/pods-without-seccomp.txt ]]; then
  echo "FAIL: /opt/cks2-seccomp/pods-without-seccomp.txt is missing or empty"
  exit 1
fi

# Check saved YAML exists and references RuntimeDefault
if [[ ! -f /opt/cks2-seccomp/no-seccomp.yaml ]]; then
  echo "FAIL: /opt/cks2-seccomp/no-seccomp.yaml not found"
  exit 1
fi
if ! grep -q "RuntimeDefault" /opt/cks2-seccomp/no-seccomp.yaml; then
  echo "FAIL: /opt/cks2-seccomp/no-seccomp.yaml does not contain RuntimeDefault"
  exit 1
fi

echo "PASS: no-seccomp pod replaced with RuntimeDefault; audit file saved; YAML saved"
