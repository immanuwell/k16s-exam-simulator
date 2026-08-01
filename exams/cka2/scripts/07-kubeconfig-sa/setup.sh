#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka2
kubectl create namespace ci-cd --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount deploy-bot -n ci-cd --dry-run=client -o yaml | kubectl apply -f -

echo "ServiceAccount deploy-bot created in namespace ci-cd"
echo "Create /opt/cka2/deploy-bot.kubeconfig using kubectl create token + kubectl config commands"
