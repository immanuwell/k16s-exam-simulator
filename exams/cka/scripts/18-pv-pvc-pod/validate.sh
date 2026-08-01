#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PV=$(kubectl get pv data-pv -o json 2>/dev/null) || {
  echo "FAIL: PersistentVolume data-pv not found"
  exit 1
}

PV_CAP=$(echo "$PV" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['capacity']['storage'])")
PV_SC=$(echo "$PV" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['storageClassName'])")
PV_POLICY=$(echo "$PV" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['persistentVolumeReclaimPolicy'])")
PV_PATH=$(echo "$PV" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('hostPath',{}).get('path',''))")

if [[ "$PV_SC" != "manual" ]]; then
  echo "FAIL: PV storageClassName should be 'manual' (got: $PV_SC)"
  exit 1
fi
if [[ "$PV_POLICY" != "Retain" ]]; then
  echo "FAIL: PV reclaimPolicy should be Retain (got: $PV_POLICY)"
  exit 1
fi
if [[ "$PV_PATH" != "/mnt/exam-data" ]]; then
  echo "FAIL: PV hostPath should be /mnt/exam-data (got: $PV_PATH)"
  exit 1
fi

PVC=$(kubectl get pvc data-pvc -n storage-demo -o json 2>/dev/null) || {
  echo "FAIL: PVC data-pvc not found in storage-demo"
  exit 1
}

PVC_STATUS=$(echo "$PVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['status']['phase'])")
if [[ "$PVC_STATUS" != "Bound" ]]; then
  echo "FAIL: PVC data-pvc is not Bound (status: $PVC_STATUS)"
  exit 1
fi

PVC_VOL=$(echo "$PVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('volumeName',''))")
if [[ "$PVC_VOL" != "data-pv" ]]; then
  echo "FAIL: PVC data-pvc is not bound to data-pv (bound to: $PVC_VOL)"
  exit 1
fi

POD=$(kubectl get pod data-pod -n storage-demo -o json 2>/dev/null) || {
  echo "FAIL: Pod data-pod not found in storage-demo"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod data-pod is not Running (phase: $PHASE)"
  exit 1
fi

MOUNT_PATH=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d['spec']['containers']:
    for vm in c.get('volumeMounts',[]):
        if vm.get('mountPath')=='/usr/share/nginx/html':
            print('ok'); sys.exit(0)
print('missing')
")
if [[ "$MOUNT_PATH" != "ok" ]]; then
  echo "FAIL: pod data-pod does not mount the PVC at /usr/share/nginx/html"
  exit 1
fi

if [[ ! -f /opt/cka/pvc-status.txt ]]; then
  echo "FAIL: /opt/cka/pvc-status.txt not saved"
  exit 1
fi

if ! grep -q 'Bound' /opt/cka/pvc-status.txt; then
  echo "FAIL: pvc-status.txt does not show Bound status"
  exit 1
fi

echo "PASS: PV data-pv (Retain/manual/hostPath) → PVC data-pvc (Bound) → Pod data-pod (Running at /usr/share/nginx/html)"
