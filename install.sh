#!/usr/bin/env bash
# CKX — Self-Hosted Kubernetes Exam Platform
# Usage:
#   On the VM directly:  bash install.sh [--profile cka] [--k8s 1.33] [--workers 2]
#   Targeting a remote:  bash install.sh --host 1.2.3.4 [--key ~/.ssh/id_ed25519]
set -euo pipefail

REMOTE_HOST=""
SSH_KEY=""
SSH_USER="root"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    REMOTE_HOST="$2";  shift 2 ;;
    --key)     SSH_KEY="$2";      shift 2 ;;
    --user)    SSH_USER="$2";     shift 2 ;;
    --profile) EXTRA_ARGS+=("--profile" "$2"); shift 2 ;;
    --k8s)     EXTRA_ARGS+=("--k8s" "$2");     shift 2 ;;
    --workers) EXTRA_ARGS+=("--workers" "$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${REMOTE_HOST}" ]]; then
  SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)
  [[ -n "${SSH_KEY}" ]] && SSH_OPTS+=(-i "${SSH_KEY}")

  echo "→ Copying CKX scripts to ${SSH_USER}@${REMOTE_HOST}:/opt/ckx ..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" "mkdir -p /opt/ckx"
  rsync -az --delete \
    "${SCRIPT_DIR}/provision/" \
    "${SCRIPT_DIR}/exams/" \
    "${SSH_USER}@${REMOTE_HOST}:/opt/ckx/" \
    2>/dev/null \
    || tar czf - -C "${SCRIPT_DIR}" provision/ exams/ \
         | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
             "cd /opt/ckx && tar xzf -"

  echo "→ Running provisioner on ${REMOTE_HOST} ..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
    "bash /opt/ckx/provision/main.sh ${EXTRA_ARGS[*]:-}"
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || { echo "Run as root or with sudo"; exit 1; }
[[ -f "${SCRIPT_DIR}/provision/main.sh" ]] || {
  echo "ERROR: provision/ directory not found. Run from the repo root."
  exit 1
}

bash "${SCRIPT_DIR}/provision/main.sh" "${EXTRA_ARGS[@]:-}"
