#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# node02 must have the required label
LABEL=$(kubectl get node node02 -o jsonpath='{.metadata.labels.accelerator}' 2>/dev/null)
if [[ "$LABEL" != "nvidia-gpu" ]]; then
  echo "FAIL: node02 does not have label accelerator=nvidia-gpu (got: '$LABEL')"
  exit 1
fi

# All pods in the deployment must be Running
RUNNING=$(kubectl get pods -n scheduling-demo --no-headers 2>/dev/null | awk '{print $3}' | grep -c "^Running$" || true)
TOTAL=$(kubectl get pods -n scheduling-demo --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$RUNNING" -lt "$TOTAL" || "$TOTAL" -eq 0 ]]; then
  echo "FAIL: not all pods are Running ($RUNNING/$TOTAL)"
  exit 1
fi

# Deployment spec must still have nodeSelector (candidate must not have changed it)
NS=$(kubectl get deployment gpu-workload -n scheduling-demo \
  -o jsonpath='{.spec.template.spec.nodeSelector.accelerator}' 2>/dev/null)
if [[ "$NS" != "nvidia-gpu" ]]; then
  echo "FAIL: Deployment nodeSelector was modified — it should still require accelerator=nvidia-gpu"
  exit 1
fi

if [[ ! -f /opt/cka/node-label.txt ]]; then
  echo "FAIL: /opt/cka/node-label.txt not saved"
  exit 1
fi

if ! grep -q 'accelerator' /opt/cka/node-label.txt; then
  echo "FAIL: node-label.txt should contain the label key=value (accelerator=nvidia-gpu)"
  exit 1
fi

echo "PASS: node02 labelled accelerator=nvidia-gpu; all gpu-workload pods Running; label saved"
