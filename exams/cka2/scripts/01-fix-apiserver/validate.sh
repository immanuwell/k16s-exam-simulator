#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Wait for apiserver to be reachable (up to 2 minutes)
echo "Waiting for kube-apiserver to be reachable..."
for i in $(seq 1 24); do
  kubectl cluster-info &>/dev/null && break
  if [[ $i -eq 24 ]]; then
    echo "FAIL: kubectl cannot reach the apiserver after 2 minutes — is the manifest fixed?"
    exit 1
  fi
  sleep 5
done

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml

# Check etcd port is correct
if grep -q 'etcd-servers=https://127.0.0.1:2380' "$MANIFEST"; then
  echo "FAIL: --etcd-servers still points to port 2380 (should be 2379)"
  exit 1
fi
if ! grep -q 'etcd-servers=https://127.0.0.1:2379' "$MANIFEST"; then
  echo "FAIL: --etcd-servers=https://127.0.0.1:2379 not found in manifest"
  exit 1
fi

# Check invalid flag is removed
if grep -q 'exam-debug-broken' "$MANIFEST"; then
  echo "FAIL: invalid flag --exam-debug-broken still present in manifest"
  exit 1
fi

# Confirm cluster is healthy
kubectl get nodes &>/dev/null || { echo "FAIL: kubectl get nodes failed"; exit 1; }

[[ -f /opt/cka2/apiserver-fix.txt ]] || {
  echo "FAIL: /opt/cka2/apiserver-fix.txt not saved"
  exit 1
}

echo "PASS: kube-apiserver manifest fixed (correct etcd port, invalid flag removed) and apiserver is healthy"
