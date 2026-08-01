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

EXAM_PROFILE="${CKX_PROFILE:-cka}"   # cka | cks | ckad
K8S_VERSION="${CKX_K8S_VERSION:-1.33}"
WORKER_COUNT="${CKX_WORKER_COUNT:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)   EXAM_PROFILE="$2"; shift 2 ;;
    --k8s)       K8S_VERSION="$2";  shift 2 ;;
    --workers)   WORKER_COUNT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

export CKX_PROFILE="${EXAM_PROFILE}"
export CKX_K8S_VERSION="${K8S_VERSION}"
export CKX_WORKER_COUNT="${WORKER_COUNT}"

log_info "Profile:         ${EXAM_PROFILE}"
log_info "Kubernetes:      v${K8S_VERSION}.x"
log_info "Worker nodes:    ${WORKER_COUNT}"
echo ""

mkdir -p /var/lib/ckx/markers

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
run_step incus        # create worker containers (image already cached)
run_step node-join
run_step candidate
run_step ttyd
run_step nginx
run_step ckx-server

PROFILE_SCRIPT="${SCRIPT_DIR}/profiles/${EXAM_PROFILE}.sh"
if [[ -f "${PROFILE_SCRIPT}" ]]; then
  log_step "Profile: ${EXAM_PROFILE}"
  bash "${PROFILE_SCRIPT}"
fi

NODE_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || hostname -I | awk '{print $1}')
PASS=$(cat /etc/ckx/candidate-password 2>/dev/null || echo "see /etc/ckx/candidate-password")

echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${GRN}  CKX provisioning complete!${RST}"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  Exam UI:      ${CYN}http://${NODE_IP}/${RST}"
echo -e "  Terminal:     ${CYN}http://${NODE_IP}/terminal/${RST}"
echo ""
echo -e "  SSH access:   ${CYN}ssh candidate@${NODE_IP}${RST}"
echo -e "  Password:     ${YEL}${PASS}${RST}"
echo ""
echo -e "  Cluster:"
kubectl get nodes -o wide 2>/dev/null || true
echo ""
