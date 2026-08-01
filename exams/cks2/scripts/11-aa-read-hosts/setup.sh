#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace apparmor-hosts --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /opt/cks2-apparmor

echo "Namespace apparmor-hosts ready — create AppArmor profile k8s-read-hosts and pod hosts-check"
