#!/usr/bin/env bash
# K16S teardown — reverses everything provision/main.sh does, in reverse order.
#
# Deliberately NOT `set -e`: every step here must survive a target that's
# missing, half-installed, or already removed (re-running this script, or
# running it against a host where install.sh died partway through, are both
# normal inputs, not error states). Individual failures are swallowed and
# the script keeps going so one missing piece can't leave everything after
# it untouched.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
# lib.sh sets its own `set -euo pipefail` (correct for every other
# provision/*.sh, which are fail-fast installers) — sourcing it re-enables
# -e here too, silently undoing the line above. Caught live: teardown died
# on the very first best-effort command that legitimately failed (`incus
# network delete` while the default profile still referenced it) instead of
# logging it and moving on to the next section like every other step here.
set +e

[[ "${EUID}" -eq 0 ]] || { echo "Run as root or with sudo" >&2; exit 1; }

ASSUME_YES="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)  ASSUME_YES="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "  ${DIM}[dry-run] $*${RST}"
  else
    # Real output shown, not swallowed — same convention install.sh's own
    # apt_install uses. Non-zero exits are expected constantly here (deleting
    # a package/interface/file that's already gone) and never abort the
    # script, since there's no `set -e` above; they just fall through.
    "$@"
  fi
}

echo -e "${YEL}This permanently removes: the kubeadm cluster and all Incus worker"
echo -e "containers, every package K16S installed (kubeadm/kubelet/kubectl,"
echo -e "containerd, incus, nginx, ttyd, the desktop stack), the candidate user"
echo -e "and its home directory, and /var/lib/k16s + /etc/k16s. This host's"
echo -e "original hostname and swap config are restored if K16S changed them.${RST}"
echo ""

if [[ "${ASSUME_YES}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Continue? [y/N] " REPLY
  [[ "${REPLY}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

[[ "${DRY_RUN}" == "true" ]] && log_warn "DRY RUN — nothing below will actually change"

source /etc/os-release 2>/dev/null || true

# ── 1. Stop services first — nothing below should race a running unit ─────

log_step "Stopping services"
for svc in k16s-server nginx k16s-terminal k16s-desktop; do
  systemctl list-unit-files "${svc}.service" &>/dev/null \
    && run systemctl disable --now "${svc}" \
    && log_ok "${svc} stopped"
done

# ── 2. k16s-server: binary, unit, and only the tools *we* provisioned ──────
# (the unit itself was already stopped/disabled by the loop above)

log_step "k16s-server"
run rm -f /etc/systemd/system/k16s-server.service /usr/local/bin/k16s-server
log_ok "k16s-server binary + unit removed"

if already_done "provisioned-node"; then
  run apt-get purge -y nodejs npm
  run rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource.sources
  run rm -f /usr/share/keyrings/nodesource.gpg
  log_ok "Node.js/npm removed (K16S installed it)"
else
  log_info "Skipping Node.js/npm — not installed by K16S"
fi

if already_done "provisioned-go"; then
  run rm -rf /usr/local/go /usr/local/bin/go /usr/local/bin/gofmt
  log_ok "Go removed (K16S installed it)"
else
  log_info "Skipping Go — not installed by K16S"
fi

if already_done "provisioned-helm"; then
  run rm -f /usr/local/bin/helm
  log_ok "helm removed (K16S installed it)"
else
  log_info "Skipping helm — not installed by K16S"
fi

if already_done "provisioned-etcdctl"; then
  run rm -f /usr/local/bin/etcdctl
  log_ok "etcdctl removed (K16S installed it)"
else
  log_info "Skipping etcdctl — not installed by K16S"
fi

# ── 3. nginx ────────────────────────────────────────────────────────────

log_step "nginx"
run rm -f /etc/nginx/sites-enabled/k16s /etc/nginx/sites-available/k16s
run apt-get purge -y nginx nginx-common
log_ok "nginx purged"

# ── 4. Desktop stack (unit already stopped/disabled above) ────────────────

log_step "Desktop (noVNC)"
run rm -f /etc/systemd/system/k16s-desktop.service /usr/local/bin/k16s-desktop-start
run rm -f /usr/share/applications/k16s-terminal.desktop /usr/share/applications/k16s-browser.desktop
run apt-get purge -y tigervnc-standalone-server tigervnc-common openbox tint2 sakura novnc websockify x11-xserver-utils
case "${ID:-}" in
  debian) run apt-get purge -y firefox-esr ;;
  ubuntu) run snap remove firefox ;;
esac
log_ok "Desktop stack purged (no-op if it was never installed)"

# ── 5. ttyd (unit already stopped/disabled above) ──────────────────────

log_step "ttyd"
run rm -f /etc/systemd/system/k16s-terminal.service /usr/local/bin/ttyd
log_ok "ttyd removed"

# ── 6. candidate user ───────────────────────────────────────────────────

log_step "candidate user"
if id candidate &>/dev/null; then
  run userdel -r candidate
  log_ok "candidate user + home directory removed"
else
  log_info "Skipping candidate user — doesn't exist"
fi
run rm -f /etc/sudoers.d/candidate

# ── 7. Incus worker containers ──────────────────────────────────────────

log_step "Incus worker containers"
if cmd_exists incus; then
  # Read the bridge's actual subnet before deleting anything — don't assume
  # the 10.10.0.0/24 default, in case K16S_INCUS_BRIDGE was customized.
  BRIDGE_PREFIX=$(incus network get incusbr0 ipv4.address 2>/dev/null | cut -d. -f1-3)

  # `-c n` restricts the CSV to just the name column — a container with more
  # than one network interface (every worker here has both eth0 and Calico's
  # vxlan.calico) makes incus emit a quoted, multi-line CSV field for IPV4,
  # and a naive `cut -d, -f1` over physical lines misreads that continuation
  # line as a second, bogus container name. Caught live: it tried to delete
  # a container literally named '10.10.0.11 (eth0)"'. Restricting the columns
  # up front sidesteps the multi-line-field problem entirely.
  while IFS= read -r NAME; do
    [[ -z "${NAME}" ]] && continue
    run incus delete "${NAME}" --force
    log_ok "Deleted container ${NAME}"
  done < <(incus list --format csv -c n 2>/dev/null)

  if [[ -n "${BRIDGE_PREFIX:-}" ]]; then
    run sed -i "/^${BRIDGE_PREFIX//./\\.}\\.[0-9]*  node[0-9]*\$/d" /etc/hosts
  fi
else
  log_info "Skipping — no incus binary, nothing to delete"
fi

# ── 8. Incus itself ──────────────────────────────────────────────────────

log_step "Incus"
if cmd_exists incus; then
  # incus-init.sh wires the `default` profile's eth0/root devices straight
  # to incusbr0/the default storage pool. Deleting every container doesn't
  # remove that profile-level reference, and incus refuses to delete a
  # network or pool that's still "in use" by it — confirmed live: this
  # failed with "Error: The network is currently in use" until the profile
  # devices were detached first.
  run incus profile device remove default eth0
  run incus profile device remove default root
  run incus network delete incusbr0
  run incus storage delete default
fi
run apt-get purge -y incus incus-client incus-base
case "${ID:-}" in
  ubuntu)
    run rm -f /etc/apt/sources.list.d/zabbly-incus-stable.list /etc/apt/keyrings/zabbly.gpg
    ;;
  debian)
    run apt-get purge -y dnsmasq-base
    ;;
esac
run rm -rf /var/lib/incus /var/lib/incus-lxcfs /var/log/incus
log_ok "Incus purged"

# ── 9. kubeadm cluster ───────────────────────────────────────────────────

log_step "kubeadm cluster"
if cmd_exists kubeadm; then
  run kubeadm reset --force
  log_ok "kubeadm reset"
fi
# Safety net for what `kubeadm reset` documents that it does NOT clean up
# on its own: iptables rules and CNI-created network interfaces. Confirmed
# live: kubeadm reset couldn't even reach Calico's own CNI delete hook (the
# API server was already down by then), so it left every per-pod Calico veth
# behind, not just the vxlan.calico overlay interface.
run iptables -F
run iptables -t nat -F
run iptables -t mangle -F
run iptables -X
for iface in $(ip -br link show 2>/dev/null | awk '{print $1}' | grep -E '^(vxlan\.calico|cali)'); do
  iface="${iface%%@*}"  # `ip -br` prints veths as "caliXXXX@if2" — strip the peer suffix
  [[ "${DRY_RUN}" == "true" ]] \
    && echo -e "  ${DIM}[dry-run] ip link delete ${iface}${RST}" \
    || ip link delete "${iface}" 2>/dev/null
done
# kubeadm reset empties these but leaves the directory trees themselves
# (confirmed live — `/etc/kubernetes/pki`, `/var/lib/etcd`, and `/etc/cni`
# all survived reset + the kubelet/incus package purges intact but empty).
run rm -rf /etc/cni /etc/kubernetes /var/lib/etcd /root/.kube

# ── 10. kubeadm/kubelet/kubectl packages ─────────────────────────────────

log_step "kubeadm / kubelet / kubectl"
run apt-mark unhold kubeadm kubelet kubectl
run apt-get purge -y kubeadm kubelet kubectl
run rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg
log_ok "kubeadm/kubelet/kubectl purged"

# ── 11. containerd ────────────────────────────────────────────────────────

log_step "containerd"
run systemctl disable --now containerd
run apt-get purge -y containerd.io
# Shared with any real Docker Engine install on this host via the same
# official repo — narrow but real edge case, not detected here. If this
# host also runs Docker, remove this repo file by hand instead of blindly
# trusting this step.
run rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
run rm -rf /var/lib/containerd /etc/containerd
log_ok "containerd purged"

# ── 12. Orphaned dependencies ─────────────────────────────────────────────
# Every `apt purge` above only removes the packages named explicitly — it
# doesn't touch what apt pulled in as *their* dependencies (confirmed live:
# python3-novnc, kubernetes-cni, dnsmasq-base and dozens of desktop/graphics
# libraries were still sitting there, installed, after every purge step above
# had already run). One autoremove at the end sweeps all of it in one pass.
log_step "Orphaned dependencies"
run apt-get autoremove --purge -y
log_ok "Orphaned packages removed"

# ── 13. Kernel config ─────────────────────────────────────────────────────

log_step "Kernel config"
run rm -f /etc/modules-load.d/k16s-k8s.conf /etc/sysctl.d/99-k16s-k8s.conf
log_info "overlay/br_netfilter kernel modules left loaded (harmless; won't reload after next reboot)"

# ── 14. Restore host state preflight.sh changed ──────────────────────────

log_step "Restoring host state"
if [[ -f /var/lib/k16s/original-hostname ]]; then
  ORIGINAL_HOSTNAME=$(cat /var/lib/k16s/original-hostname)
  run hostnamectl set-hostname "${ORIGINAL_HOSTNAME}"
  run sed -i '/^127\.0\.1\.1  k16s$/d' /etc/hosts
  log_ok "Hostname restored to ${ORIGINAL_HOSTNAME}"
else
  log_info "Skipping hostname restore — was already k16s before K16S ran, or install.sh never ran"
fi

if [[ -f /var/lib/k16s/original-fstab-swap && -s /var/lib/k16s/original-fstab-swap ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "  ${DIM}[dry-run] restore swap line(s) to /etc/fstab and swapon -a${RST}"
  else
    cat /var/lib/k16s/original-fstab-swap >> /etc/fstab
    swapon -a &>/dev/null
  fi
  log_ok "Swap restored"
else
  log_info "Skipping swap restore — none was enabled before K16S ran"
fi

# ── 15. K16S's own state — last, since earlier steps read it ─────────────

log_step "K16S state directories"
run rm -f /var/log/k16s-node*.log /var/log/kubeadm-init.log /var/log/k16s-incus-prefetch.log
run rm -rf /var/lib/k16s /etc/k16s
log_ok "/var/lib/k16s, /etc/k16s, and leftover /var/log/k16s-*.log removed"

echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${YEL}Dry run complete — nothing was actually changed.${RST}"
else
  echo -e "${GRN}K16S fully removed.${RST}"
fi
echo ""
