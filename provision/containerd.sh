#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "containerd"

already_done "containerd" && { log_skip "containerd"; exit 0; }

source /etc/os-release

apt_install curl ca-certificates gnupg2

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/${ID}/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# trixie not in Docker's repo yet — fall back to bookworm
case "${VERSION_CODENAME}" in
  trixie) REPO_CODENAME="bookworm" ;;
  *)      REPO_CODENAME="${VERSION_CODENAME}" ;;
esac

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${REPO_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt_install containerd.io
log_ok "containerd.io installed"

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml \
  || die "Failed to set SystemdCgroup = true in containerd config"

systemctl enable --now containerd
systemctl restart containerd
log_ok "containerd configured (SystemdCgroup=true) and started"

mark_done "containerd"
