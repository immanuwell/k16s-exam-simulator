#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2 /mnt/archive-data

kubectl create namespace archive-ns --dry-run=client -o yaml | kubectl apply -f -

# Clean up any prior state
kubectl delete pod archive-pod -n archive-ns 2>/dev/null || true
kubectl delete pvc archive-new archive-claim -n archive-ns 2>/dev/null || true
sleep 2
kubectl delete pv recovered-data 2>/dev/null || true
sleep 2

# Create the PV
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: recovered-data
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath:
    path: /mnt/archive-data
EOF

# Create a temporary PVC to bind it, then delete it — leaving PV in Released state
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-claim
  namespace: archive-ns
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: archive
  volumeName: recovered-data
EOF

# Wait for PVC to bind
for i in $(seq 1 20); do
  STATUS=$(kubectl get pvc archive-claim -n archive-ns -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$STATUS" == "Bound" ]] && break
  sleep 3
done

# Delete the PVC — PV becomes Released (claimRef retained)
kubectl delete pvc archive-claim -n archive-ns 2>/dev/null || true

sleep 2

echo "PV recovered-data is now in Released state — remove claimRef and bind a new PVC"
