#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Bad flag must be gone from the manifest
if grep -q '\-\-invalid-scheduling-mode' /etc/kubernetes/manifests/kube-scheduler.yaml; then
  echo "FAIL: --invalid-scheduling-mode is still present in kube-scheduler.yaml"
  exit 1
fi

# Scheduler pod must be Running
for i in {1..12}; do
  PHASE=$(kubectl get pod -n kube-system -l component=kube-scheduler \
    --no-headers 2>/dev/null | awk '{print $3}' | head -1)
  [[ "$PHASE" == "Running" ]] && break
  sleep 5
done

PHASE=$(kubectl get pod -n kube-system -l component=kube-scheduler \
  --no-headers 2>/dev/null | awk '{print $3}' | head -1)
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: kube-scheduler pod is not Running (phase: $PHASE)"
  exit 1
fi

if [[ ! -f /opt/cka/scheduler-fix.txt ]]; then
  echo "FAIL: /opt/cka/scheduler-fix.txt not saved"
  exit 1
fi

if ! grep -q 'invalid-scheduling-mode' /opt/cka/scheduler-fix.txt; then
  echo "FAIL: scheduler-fix.txt should contain the name of the removed flag"
  exit 1
fi

echo "PASS: invalid flag removed; kube-scheduler is Running; fix recorded"
