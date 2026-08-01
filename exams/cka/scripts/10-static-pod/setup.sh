#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Clean up any previous static pod manifest from a prior attempt
incus exec node01 -- rm -f /etc/kubernetes/manifests/static-busybox.yaml 2>/dev/null || true

echo "Environment ready — SSH to node01 and create the static pod manifest"
