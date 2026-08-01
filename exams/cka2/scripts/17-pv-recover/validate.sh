#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

PV=$(kubectl get pv recovered-data -o json 2>/dev/null) || {
  echo "FAIL: PersistentVolume recovered-data not found"
  exit 1
}

PV_PHASE=$(echo "$PV" | python3 -c "import sys,json; print(json.load(sys.stdin)['status']['phase'])")
if [[ "$PV_PHASE" != "Bound" ]]; then
  echo "FAIL: PV recovered-data is in phase '$PV_PHASE' (should be Bound after new PVC binds to it)"
  exit 1
fi

PVC=$(kubectl get pvc archive-new -n archive-ns -o json 2>/dev/null) || {
  echo "FAIL: PVC archive-new not found in archive-ns"
  exit 1
}

PVC_PHASE=$(echo "$PVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['status']['phase'])")
if [[ "$PVC_PHASE" != "Bound" ]]; then
  echo "FAIL: PVC archive-new is $PVC_PHASE (expected Bound)"
  exit 1
fi

PVC_VOL=$(echo "$PVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('volumeName',''))")
if [[ "$PVC_VOL" != "recovered-data" ]]; then
  echo "FAIL: PVC archive-new is not bound to recovered-data (volumeName=$PVC_VOL)"
  exit 1
fi

POD=$(kubectl get pod archive-pod -n archive-ns -o json 2>/dev/null) || {
  echo "FAIL: Pod archive-pod not found in archive-ns"
  exit 1
}

POD_PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$POD_PHASE" != "Running" ]]; then
  echo "FAIL: pod archive-pod is $POD_PHASE (expected Running)"
  exit 1
fi

MOUNT_OK=$(echo "$POD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d['spec']['containers']:
    for vm in c.get('volumeMounts', []):
        if vm.get('mountPath') == '/data':
            print('ok'); exit()
print('missing')
")
if [[ "$MOUNT_OK" != "ok" ]]; then
  echo "FAIL: pod archive-pod does not mount the PVC at /data"
  exit 1
fi

[[ -f /opt/cka2/pv-recover.txt ]] || {
  echo "FAIL: /opt/cka2/pv-recover.txt not saved"
  exit 1
}

echo "PASS: Released PV recovered-data successfully rebound to PVC archive-new; pod archive-pod Running with /data mount"
