#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check PV
PV_CAPACITY=$(kubectl get pv data-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)
if [[ -z "${PV_CAPACITY}" ]]; then
  echo "FAIL: PersistentVolume 'data-pv' not found"
  exit 1
fi

PV_SC=$(kubectl get pv data-pv -o jsonpath='{.spec.storageClassName}')
if [[ "${PV_SC}" != "manual" ]]; then
  echo "FAIL: PV storageClassName should be 'manual', got '${PV_SC}'"
  exit 1
fi

PV_POLICY=$(kubectl get pv data-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
if [[ "${PV_POLICY}" != "Retain" ]]; then
  echo "FAIL: PV reclaimPolicy should be 'Retain', got '${PV_POLICY}'"
  exit 1
fi

PV_PATH=$(kubectl get pv data-pv -o jsonpath='{.spec.hostPath.path}')
if [[ "${PV_PATH}" != "/mnt/data" ]]; then
  echo "FAIL: PV hostPath should be '/mnt/data', got '${PV_PATH}'"
  exit 1
fi

# Check PVC
PVC_STATUS=$(kubectl get pvc data-pvc -n default -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "${PVC_STATUS}" != "Bound" ]]; then
  echo "FAIL: PVC 'data-pvc' status is '${PVC_STATUS}', expected 'Bound'"
  exit 1
fi

PVC_SC=$(kubectl get pvc data-pvc -n default -o jsonpath='{.spec.storageClassName}')
if [[ "${PVC_SC}" != "manual" ]]; then
  echo "FAIL: PVC storageClassName should be 'manual', got '${PVC_SC}'"
  exit 1
fi

echo "PASS: PV data-pv (${PV_CAPACITY}, Retain, /mnt/data) and PVC data-pvc (Bound, manual) are correctly configured"
