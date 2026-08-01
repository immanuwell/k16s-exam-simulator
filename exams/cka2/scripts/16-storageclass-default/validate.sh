#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

SC=$(kubectl get storageclass fast-storage -o json 2>/dev/null) || {
  echo "FAIL: StorageClass fast-storage not found"
  exit 1
}

BIND_MODE=$(echo "$SC" | python3 -c "import sys,json; print(json.load(sys.stdin).get('volumeBindingMode','missing'))")
if [[ "$BIND_MODE" != "WaitForFirstConsumer" ]]; then
  echo "FAIL: StorageClass volumeBindingMode is $BIND_MODE (expected WaitForFirstConsumer)"
  exit 1
fi

IS_DEFAULT=$(echo "$SC" | python3 -c "
import sys, json
d = json.load(sys.stdin)
annotations = d.get('metadata', {}).get('annotations', {})
print(annotations.get('storageclass.kubernetes.io/is-default-class', 'false'))
")
if [[ "$IS_DEFAULT" != "true" ]]; then
  echo "FAIL: StorageClass fast-storage is not marked as default (annotation is-default-class=$IS_DEFAULT)"
  exit 1
fi

# Check PVC uses the default StorageClass
PVC=$(kubectl get pvc test-claim -n storage-test -o json 2>/dev/null) || {
  echo "FAIL: PVC test-claim not found in storage-test"
  exit 1
}

PVC_SC=$(echo "$PVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('storageClassName','missing'))")
if [[ "$PVC_SC" != "fast-storage" ]]; then
  echo "FAIL: PVC test-claim storageClassName is '$PVC_SC' (expected 'fast-storage' — from default)"
  exit 1
fi

[[ -f /opt/cka2/storageclass.txt ]] || {
  echo "FAIL: /opt/cka2/storageclass.txt not saved"
  exit 1
}

echo "PASS: StorageClass fast-storage (WaitForFirstConsumer, default=true); PVC test-claim uses it"
