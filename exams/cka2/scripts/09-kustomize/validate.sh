#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

[[ -f /opt/cka2/kustomize-output.yaml ]] || {
  echo "FAIL: /opt/cka2/kustomize-output.yaml not found (run: kubectl kustomize ... > /opt/cka2/kustomize-output.yaml)"
  exit 1
}

# Check rendered output has replicas: 3
if ! grep -q 'replicas: 3' /opt/cka2/kustomize-output.yaml; then
  echo "FAIL: kustomize-output.yaml does not contain replicas: 3"
  exit 1
fi

# Check deployment web exists in kustomize-demo
DEPLOY=$(kubectl get deployment web -n kustomize-demo -o json 2>/dev/null) || {
  echo "FAIL: deployment web not found in namespace kustomize-demo — did you apply the overlay?"
  exit 1
}

REPLICAS=$(echo "$DEPLOY" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['replicas'])")
if [[ "$REPLICAS" -ne 3 ]]; then
  echo "FAIL: deployment web has $REPLICAS replicas (expected 3)"
  exit 1
fi

# Check env=production label on pods
ENV_LABEL=$(echo "$DEPLOY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['spec']['template']['metadata'].get('labels', {}).get('env', 'missing'))
")
if [[ "$ENV_LABEL" != "production" ]]; then
  echo "FAIL: pod template does not have label env=production (got: $ENV_LABEL)"
  exit 1
fi

echo "PASS: kustomize overlay applied — web deployment has 3 replicas with env=production label in kustomize-demo"
