#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

echo -e "${CYN}"
echo "  ██████╗██╗  ██╗██╗  ██╗"
echo " ██╔════╝██║ ██╔╝╚██╗██╔╝"
echo " ██║     █████╔╝  ╚███╔╝ "
echo " ██║     ██╔═██╗  ██╔██╗ "
echo " ╚██████╗██║  ██╗██╔╝ ██╗"
echo "  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝"
echo -e "${RST}"
echo "  Kubernetes Exam Platform — Provisioner"
echo "  ─────────────────────────────────────"
echo ""

EXAM_PROFILE="${K16S_PROFILE:-cka}"   # cka | cks | ckad
K8S_VERSION="${K16S_K8S_VERSION:-1.33}"
WORKER_COUNT="${K16S_WORKER_COUNT:-1}"
DESKTOP_ENABLED="${K16S_DESKTOP:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)     EXAM_PROFILE="$2"; shift 2 ;;
    --k8s)         K8S_VERSION="$2";  shift 2 ;;
    --workers)     WORKER_COUNT="$2"; shift 2 ;;
    --no-desktop)  DESKTOP_ENABLED="false"; shift ;;
    --desktop)     DESKTOP_ENABLED="true"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

export K16S_PROFILE="${EXAM_PROFILE}"
export K16S_K8S_VERSION="${K8S_VERSION}"
export K16S_WORKER_COUNT="${WORKER_COUNT}"
export K16S_DESKTOP="${DESKTOP_ENABLED}"

log_info "Profile:         ${EXAM_PROFILE}"
log_info "Kubernetes:      v${K8S_VERSION}.x"
log_info "Worker nodes:    ${WORKER_COUNT}"
log_info "Web desktop:     ${DESKTOP_ENABLED}"
echo ""

mkdir -p /var/lib/k16s/markers

run_step() {
  local script="${SCRIPT_DIR}/${1}.sh"
  [[ -f "${script}" ]] || die "Step script not found: ${script}"
  bash "${script}"
}

run_step preflight
run_step kernel
run_step containerd
run_step incus-init   # install Incus + start base image download in background
run_step kubeadm      # ← image downloads in parallel with this
run_step cluster-init # ← and this
run_step cni          # ← and this; image ready by the time we need containers
run_step metrics-server # control plane is untainted, so this can run before workers exist
run_step incus        # create worker containers (image already cached)
run_step node-join
run_step node-ssh     # workers need sshd before `ssh node01` can work
run_step candidate
run_step ttyd
if [[ "${DESKTOP_ENABLED}" == "true" ]]; then
  run_step desktop
else
  log_skip "desktop (K16S_DESKTOP=false)"
fi
run_step nginx
run_step k16s-server

PROFILE_SCRIPT="${SCRIPT_DIR}/profiles/${EXAM_PROFILE}.sh"
if [[ -f "${PROFILE_SCRIPT}" ]]; then
  log_step "Profile: ${EXAM_PROFILE}"
  bash "${PROFILE_SCRIPT}"
fi

NODE_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || hostname -I | awk '{print $1}')
PASS=$(cat /etc/k16s/candidate-password 2>/dev/null || echo "see /etc/k16s/candidate-password")

echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${GRN}  K16S provisioning complete!${RST}"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  Exam UI:      ${CYN}http://${NODE_IP}/${RST}"
echo -e "  Terminal:     ${CYN}http://${NODE_IP}/terminal/${RST}"
echo -e "  Desktop:      ${CYN}http://${NODE_IP}/desktop/vnc_lite.html?autoconnect=true&resize=remote&path=desktop/websockify${RST}"
echo ""
echo -e "  SSH access:   ${CYN}ssh candidate@${NODE_IP}${RST}"
echo -e "  Password:     ${YEL}${PASS}${RST}"
echo ""
echo -e "  Cluster:"
kubectl get nodes -o wide 2>/dev/null || true
echo ""
