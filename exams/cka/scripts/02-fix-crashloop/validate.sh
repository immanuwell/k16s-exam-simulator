#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# ConfigMap must exist
kubectl get configmap app-config -n crash-demo >/dev/null 2>&1 || {
  echo "FAIL: ConfigMap app-config not found in namespace crash-demo"
  exit 1
}

# Pod must be Running
for i in {1..6}; do
  PHASE=$(kubectl get pod api-server -n crash-demo -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && break
  sleep 5
done

PHASE=$(kubectl get pod api-server -n crash-demo -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod api-server is not Running (phase: $PHASE)"
  exit 1
fi

# Pod spec must not be changed (still references app-config)
ENVFROM=$(kubectl get pod api-server -n crash-demo -o jsonpath='{.spec.containers[0].envFrom[0].configMapRef.name}' 2>/dev/null)
if [[ "$ENVFROM" != "app-config" ]]; then
  echo "FAIL: pod spec was modified — envFrom.configMapRef.name should be app-config (got: $ENVFROM)"
  exit 1
fi

if [[ ! -f /opt/cka/crashloop-fix.txt ]]; then
  echo "FAIL: /opt/cka/crashloop-fix.txt not saved"
  exit 1
fi

echo "PASS: ConfigMap app-config created; pod api-server is Running; fix file saved"
