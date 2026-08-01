#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Incus (worker node containers)"

already_done "incus" && { log_skip "Incus setup"; exit 0; }

WORKER_COUNT="${CKX_WORKER_COUNT:-2}"
BRIDGE_ADDR="${CKX_INCUS_BRIDGE:-10.10.0.1/24}"
NODE_IMG="${CKX_NODE_IMAGE:-debian/12}"

NET_BASE=$(echo "${BRIDGE_ADDR}" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')
NODE_IP_START=11

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
https://pkgs.zabbly.com/incus/stable $(. /etc/os-release; echo ${VERSION_CODENAME}) main" \
        > /etc/apt/sources.list.d/zabbly-incus-stable.list
      apt-get update -q
      apt_install incus
      ;;
  esac
fi
log_ok "Incus installed ($(incus version 2>/dev/null | head -1))"

_incus_initialized() {
  incus storage list 2>/dev/null | grep -q default \
    && incus network list 2>/dev/null | grep -q incusbr0 \
    && incus profile show default 2>/dev/null | grep -q "pool: default"
}

if ! _incus_initialized; then
  log_info "Initializing Incus..."

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

  log_ok "Incus initialized"
else
  log_skip "Incus already initialized"
fi

# Containers share the host kernel — ensure modules are loaded on host
modprobe overlay
modprobe br_netfilter
log_ok "Host kernel modules ready for container use"

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  NODE_IP="${NET_BASE}.$((NODE_IP_START + i - 1))"

  if incus list --format csv | grep -q "^${NAME},"; then
    log_skip "Container ${NAME} already exists"
    continue
  fi

  log_info "Creating container ${NAME} (IP: ${NODE_IP})..."

  incus launch "images:${NODE_IMG}" "${NAME}"

  incus config device override "${NAME}" eth0 \
    ipv4.address="${NODE_IP}" 2>/dev/null || true

  incus config set "${NAME}" \
    security.privileged=true \
    security.nesting=true \
    linux.kernel_modules="overlay,br_netfilter,ip_tables,ip6_tables,nf_conntrack"

  incus config set "${NAME}" raw.lxc "$(cat <<'RAWLXC'
lxc.apparmor.profile=unconfined
lxc.cap.drop=
lxc.mount.auto=proc:rw sys:rw cgroup:rw:force
RAWLXC
)"

  # kubelet requires /dev/kmsg; not exposed in LXC containers by default
  incus config device add "${NAME}" kmsg unix-char source=/dev/kmsg path=/dev/kmsg 2>/dev/null || true

  incus stop "${NAME}" --force 2>/dev/null || true
  incus start "${NAME}"

  log_ok "Container ${NAME} created at ${NODE_IP}"
done

log_info "Waiting for containers to boot..."
for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  for attempt in $(seq 1 20); do
    if incus exec "${NAME}" -- systemctl is-system-running --quiet 2>/dev/null | grep -qE "running|degraded"; then
      break
    fi
    sleep 3
  done
  log_ok "Container ${NAME} is running"
done

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  NODE_IP="${NET_BASE}.$((NODE_IP_START + i - 1))"
  grep -q "^${NODE_IP} " /etc/hosts || echo "${NODE_IP}  ${NAME}" >> /etc/hosts
done

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  incus exec "${NAME}" -- hostnamectl set-hostname "${NAME}" 2>/dev/null || \
    incus exec "${NAME}" -- hostname "${NAME}"
  incus exec "${NAME}" -- bash -c \
    "grep -q '127.0.1.1.*${NAME}' /etc/hosts || echo '127.0.1.1  ${NAME}' >> /etc/hosts"
done

log_ok "Incus setup complete: ${WORKER_COUNT} worker containers ready"
mark_done "incus"
