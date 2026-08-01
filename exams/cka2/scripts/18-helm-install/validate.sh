#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check helm is available
command -v helm &>/dev/null || {
  echo "FAIL: helm binary not found"
  exit 1
}

[[ -f /opt/cka2/webapp-manifest.yaml ]] || {
  echo "FAIL: /opt/cka2/webapp-manifest.yaml not found (run: helm template webapp /opt/cka2/charts/webapp/ --skip-crds > /opt/cka2/webapp-manifest.yaml)"
  exit 1
}

# Check rendered manifest contains a Deployment
if ! grep -q 'kind: Deployment' /opt/cka2/webapp-manifest.yaml; then
  echo "FAIL: webapp-manifest.yaml does not contain a Deployment"
  exit 1
fi

# Check Helm release exists
RELEASE=$(helm list -n helm-demo -o json 2>/dev/null)
STATUS=$(echo "$RELEASE" | python3 -c "
import sys, json
releases = json.load(sys.stdin)
for r in releases:
    if r.get('name') == 'webapp':
        print(r.get('status', 'unknown')); exit()
print('missing')
")
if [[ "$STATUS" != "deployed" ]]; then
  echo "FAIL: Helm release 'webapp' in namespace helm-demo is '$STATUS' (expected 'deployed')"
  exit 1
fi

# Check deployment is running
READY=$(kubectl get deployment -n helm-demo -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "FAIL: no ready replicas in helm-demo namespace"
  exit 1
fi

[[ -f /opt/cka2/helm-list.txt ]] || {
  echo "FAIL: /opt/cka2/helm-list.txt not saved"
  exit 1
}

echo "PASS: Helm chart templated to /opt/cka2/webapp-manifest.yaml; release 'webapp' deployed in helm-demo (ready=$READY)"
