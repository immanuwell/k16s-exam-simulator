#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "kubeadm / kubelet / kubectl"

already_done "kubeadm" && { log_skip "kubeadm"; exit 0; }

# v1.31 repo uses PGP v3 keys rejected by Debian 13's sqv verifier; use ≥1.32
K8S_VERSION="${K16S_K8S_VERSION:-1.33}"

apt_install curl ca-certificates gnupg2 apt-transport-https

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -q
apt_install kubeadm kubelet kubectl
log_ok "Installed kubeadm, kubelet, kubectl (v${K8S_VERSION}.x)"

apt-mark hold kubelet kubeadm kubectl
log_ok "Packages held at current version"

systemctl enable kubelet
log_ok "kubelet enabled"

mark_done "kubeadm"
