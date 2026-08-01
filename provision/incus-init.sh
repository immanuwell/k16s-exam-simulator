#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Incus install + network init"

NODE_IMG="${CKX_NODE_IMAGE:-debian/12}"
BRIDGE_ADDR="${CKX_INCUS_BRIDGE:-10.10.0.1/24}"
NET_BASE=$(echo "${BRIDGE_ADDR}" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')
PREFETCH_PID_FILE="/var/lib/ckx/incus-prefetch.pid"

_start_prefetch() {
  if incus image list local: --format csv 2>/dev/null | grep -q "debian/12"; then
    log_ok "Base image already in local cache"
    return
  fi
  log_info "Downloading Incus base image in background (overlaps with kubeadm setup)..."
  nohup incus image copy "images:${NODE_IMG}" local: --copy-aliases \
    > /var/log/ckx-incus-prefetch.log 2>&1 &
  echo $! > "${PREFETCH_PID_FILE}"
}

if already_done "incus-init"; then
  log_skip "Incus already installed and initialized"
  _start_prefetch
  exit 0
fi

# ── Install Incus ─────────────────────────────────────────────────────────

if ! cmd_exists incus; then
  source /etc/os-release
  case "${ID}" in
    debian)
      apt-get update -q
      apt_install incus dnsmasq-base
      ;;
    ubuntu)
      curl -fsSL https://pkgs.zabbly.com/key.asc \
        | gpg --dearmor --yes -o /etc/apt/keyrings/zabbly.gpg
      echo "deb [signed-by=/etc/apt/keyrings/zabbly.gpg] \
https://pkgs.zabbly.com/incus/stable $(. /etc/os-release; echo "${VERSION_CODENAME}") main" \
        > /etc/apt/sources.list.d/zabbly-incus-stable.list
      apt-get update -q
      apt_install incus
      ;;
    *) die "Unsupported OS: ${ID}" ;;
  esac
fi
log_ok "Incus $(incus version 2>/dev/null | head -1)"

# ── Initialize storage, bridge network, default profile ───────────────────

incus storage list 2>/dev/null | grep -q default \
  || incus storage create default dir

incus network list 2>/dev/null | grep -q incusbr0 \
  || incus network create incusbr0 \
       ipv4.address="${BRIDGE_ADDR}" \
       ipv4.dhcp=true \
       "ipv4.dhcp.ranges=${NET_BASE}.2-${NET_BASE}.50" \
       ipv4.nat=true \
       ipv6.address=none

incus profile show default 2>/dev/null | grep -q "pool: default" || {
  incus profile device add default root disk path=/ pool=default size=8GB 2>/dev/null || true
  incus profile device add default eth0 nic nictype=bridged parent=incusbr0 2>/dev/null || true
}

modprobe overlay
modprobe br_netfilter

mark_done "incus-init"
log_ok "Incus initialized"

# ── Start base image download in background ───────────────────────────────
# The image download runs concurrently with kubeadm + cluster-init + cni,
# so it costs no wall-clock time by the time incus.sh creates containers.

_start_prefetch
