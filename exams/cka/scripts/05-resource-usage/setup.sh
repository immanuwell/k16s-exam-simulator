#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

echo "Environment ready — use kubectl top to find resource-consuming pods and nodes"
