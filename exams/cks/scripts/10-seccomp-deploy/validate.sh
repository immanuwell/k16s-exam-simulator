#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

DEPLOY="seccomp-app"
NS="seccomp-apps"

READY=$(kubectl get deployment "$DEPLOY" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
DESIRED=$(kubectl get deployment "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [[ "$READY" != "$DESIRED" || -z "$READY" ]]; then
  echo "FAIL: deployment $DEPLOY in $NS not ready (${READY:-0}/$DESIRED)"
  exit 1
fi

# Check seccompProfile.type=RuntimeDefault on pod template
TYPE=$(kubectl get deployment "$DEPLOY" -n "$NS" \
  -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' 2>/dev/null)
if [[ "$TYPE" != "RuntimeDefault" ]]; then
  echo "FAIL: deployment pod template seccompProfile.type is '${TYPE:-unset}', expected RuntimeDefault"
  exit 1
fi

if [[ ! -f /opt/cks-seccomp/seccomp-type.txt ]]; then
  echo "FAIL: seccomp type not saved to /opt/cks-seccomp/seccomp-type.txt"
  exit 1
fi

if ! grep -q "RuntimeDefault" /opt/cks-seccomp/seccomp-type.txt; then
  echo "FAIL: /opt/cks-seccomp/seccomp-type.txt does not contain 'RuntimeDefault'"
  exit 1
fi

echo "PASS: deployment seccomp-app uses RuntimeDefault seccomp; all replicas ready"
