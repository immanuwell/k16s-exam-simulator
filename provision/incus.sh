#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Incus worker containers"

already_done "incus" && { log_skip "Incus containers"; exit 0; }

WORKER_COUNT="${K16S_WORKER_COUNT:-1}"
BRIDGE_ADDR="${K16S_INCUS_BRIDGE:-10.10.0.1/24}"
NODE_IMG="${K16S_NODE_IMAGE:-debian/12}"

NET_BASE=$(echo "${BRIDGE_ADDR}" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')
NODE_IP_START=11

# ── Ensure Incus is ready (self-contained fallback if incus-init wasn't run) ──

if ! cmd_exists incus; then
  die "Incus is not installed — run incus-init step first"
fi

_incus_initialized() {
  incus storage list 2>/dev/null | grep -q default \
    && incus network list 2>/dev/null | grep -q incusbr0
}

if ! _incus_initialized; then
  die "Incus is not initialized — run incus-init step first"
fi

modprobe overlay
modprobe br_netfilter

# ── Wait for background image prefetch ────────────────────────────────────
# incus-init.sh started the download in background; wait for it here so the
# container launches use the local cache instead of re-downloading.

PREFETCH_PID_FILE="/var/lib/k16s/incus-prefetch.pid"
if [[ -f "${PREFETCH_PID_FILE}" ]]; then
  PID=$(cat "${PREFETCH_PID_FILE}")
  if kill -0 "${PID}" 2>/dev/null; then
    log_info "Waiting for base image download to complete..."
    wait "${PID}" 2>/dev/null || true
  fi
  rm -f "${PREFETCH_PID_FILE}"
fi

# Determine launch image: prefer local cache (faster), fallback to remote
if incus image list local: --format csv 2>/dev/null | grep -q "debian/12"; then
  LAUNCH_IMAGE="local:debian/12"
  log_ok "Using locally cached base image"
else
  LAUNCH_IMAGE="images:${NODE_IMG}"
  log_info "Base image not in local cache — will download during launch"
fi

# ── Create worker containers ───────────────────────────────────────────────

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  NODE_IP="${NET_BASE}.$((NODE_IP_START + i - 1))"

  if incus list --format csv 2>/dev/null | grep -q "^${NAME},"; then
    log_skip "Container ${NAME} already exists"
    continue
  fi

  log_info "Creating container ${NAME} (${NODE_IP})..."
  incus launch "${LAUNCH_IMAGE}" "${NAME}"

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
  for _ in $(seq 1 20); do
    if incus exec "${NAME}" -- systemctl is-system-running --quiet 2>/dev/null; then
      break
    fi
    sleep 3
  done
  log_ok "Container ${NAME} is up"
done

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  NODE_IP="${NET_BASE}.$((NODE_IP_START + i - 1))"
  grep -q "^${NODE_IP} " /etc/hosts || echo "${NODE_IP}  ${NAME}" >> /etc/hosts
done

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  incus exec "${NAME}" -- hostnamectl set-hostname "${NAME}" 2>/dev/null \
    || incus exec "${NAME}" -- hostname "${NAME}"
  incus exec "${NAME}" -- bash -c \
    "grep -q '127.0.1.1.*${NAME}' /etc/hosts || echo '127.0.1.1  ${NAME}' >> /etc/hosts"
done

log_ok "Incus: ${WORKER_COUNT} worker container(s) ready"
mark_done "incus"
