#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace apparmor-2 --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /opt/cks2-apparmor

echo "Namespace apparmor-2 ready — create the AppArmor profile k8s-allow-tmp and pod tmp-writer"
