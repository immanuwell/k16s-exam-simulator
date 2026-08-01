#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2

# Save a clean backup so candidate can reference it if needed
cp /etc/kubernetes/manifests/kube-apiserver.yaml /opt/cka2/kube-apiserver.yaml.bak

# Inject two problems:
# 1. Wrong etcd client port (2380 is the peer port, not the client port 2379)
sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:2380|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# 2. Add an unrecognised flag that causes the binary to exit immediately
sed -i '/- kube-apiserver/a\    - --exam-debug-broken=yes' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

echo "kube-apiserver manifest broken — kubectl will stop responding"
