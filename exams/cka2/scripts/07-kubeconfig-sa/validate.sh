#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

[[ -f /opt/cka2/deploy-bot.kubeconfig ]] || {
  echo "FAIL: /opt/cka2/deploy-bot.kubeconfig not found"
  exit 1
}

KC=/opt/cka2/deploy-bot.kubeconfig

# Check cluster server is set
SERVER=$(kubectl config view --kubeconfig="$KC" \
  -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
[[ -n "$SERVER" ]] || {
  echo "FAIL: no cluster server found in deploy-bot.kubeconfig"
  exit 1
}

# Check a token credential is present
TOKEN=$(kubectl config view --kubeconfig="$KC" --raw \
  -o jsonpath='{.users[0].user.token}' 2>/dev/null)
[[ -n "$TOKEN" ]] || {
  echo "FAIL: no token found for user in deploy-bot.kubeconfig"
  exit 1
}

# Check a context is set
CTX=$(kubectl config view --kubeconfig="$KC" \
  -o jsonpath='{.current-context}' 2>/dev/null)
[[ -n "$CTX" ]] || {
  echo "FAIL: no current-context set in deploy-bot.kubeconfig"
  exit 1
}

# Verify the kubeconfig can reach the cluster
kubectl --kubeconfig="$KC" cluster-info &>/dev/null || {
  echo "FAIL: kubectl --kubeconfig=$KC cluster-info failed (token may be expired or invalid)"
  exit 1
}

[[ -f /opt/cka2/deploy-bot-cluster-info.txt ]] || {
  echo "FAIL: /opt/cka2/deploy-bot-cluster-info.txt not saved"
  exit 1
}

echo "PASS: deploy-bot.kubeconfig has server=$SERVER, token set, context=$CTX, and cluster-info works"
