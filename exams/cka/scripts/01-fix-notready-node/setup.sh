#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Stop kubelet inside the node01 Incus container
incus exec node01 -- systemctl stop kubelet

echo "node01 kubelet stopped — node will appear NotReady within ~40 seconds"
