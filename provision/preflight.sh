#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Preflight checks"

[[ -f /etc/os-release ]] || die "Cannot read /etc/os-release — unsupported OS"
source /etc/os-release

case "${ID}" in
  debian)
    [[ "${VERSION_ID}" == "13" ]] || die "Debian 13 (trixie) required, got Debian ${VERSION_ID}"
    log_ok "OS: Debian ${VERSION_ID} (${VERSION_CODENAME})"
    ;;
  ubuntu)
    case "${VERSION_ID}" in
      22.04|24.04) log_ok "OS: Ubuntu ${VERSION_ID}" ;;
      *) die "Ubuntu 22.04 or 24.04 required, got ${VERSION_ID}" ;;
    esac
    ;;
  *)
    die "Unsupported OS '${ID}'. Supported: debian 13, ubuntu 22.04/24.04"
    ;;
esac

[[ "${EUID}" -eq 0 ]] || die "Must run as root"
log_ok "Running as root"

CPUS=$(nproc)
[[ "${CPUS}" -ge 2 ]] || die "Need at least 2 CPUs, got ${CPUS}"
log_ok "CPUs: ${CPUS}"

MEM_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
[[ "${MEM_MB}" -ge 3800 ]] || die "Need at least 4GB RAM, got ${MEM_MB}MB"
log_ok "RAM: ${MEM_MB}MB"

DISK_FREE_MB=$(df / | awk 'NR==2 { printf "%d", $4/1024 }')
[[ "${DISK_FREE_MB}" -ge 20480 ]] || die "Need at least 20GB free on /, got ${DISK_FREE_MB}MB"
log_ok "Disk free: ${DISK_FREE_MB}MB"

SWAP=$(swapon --show --noheadings 2>/dev/null | wc -l)
if [[ "${SWAP}" -gt 0 ]]; then
  log_warn "Swap is enabled — disabling (required by kubelet)"
  swapoff -a
  sed -i '/\bswap\b/d' /etc/fstab
fi
log_ok "Swap: disabled"

grep -q cgroup2 /proc/mounts || die "cgroup v2 not mounted — kernel or systemd too old"
log_ok "cgroup v2 mounted"

if [[ "$(hostname)" != "k16s" ]]; then
  hostnamectl set-hostname k16s
  log_info "Hostname set to k16s"
fi
log_ok "Hostname: $(hostname)"

grep -q "$(hostname)" /etc/hosts || echo "127.0.1.1  $(hostname)" >> /etc/hosts

log_ok "Preflight passed"
