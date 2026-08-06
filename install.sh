#!/usr/bin/env bash
# K16S — Self-Hosted Kubernetes Exam Platform
# Usage:
#   On the VM directly:  bash install.sh [--profile cka] [--k8s 1.33] [--workers 1]
#   Targeting a remote:  bash install.sh --host 1.2.3.4 [--key ~/.ssh/id_ed25519]
#   On your laptop:      bash install.sh --laptop [--profile cka] [--cpus 4] [--memory 8]
set -euo pipefail

REMOTE_HOST=""
SSH_KEY=""
SSH_USER="root"
LAPTOP="false"
EXTRA_ARGS=()
LAPTOP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    REMOTE_HOST="$2";  shift 2 ;;
    --key)     SSH_KEY="$2";      shift 2 ;;
    --user)    SSH_USER="$2";     shift 2 ;;
    --laptop)     LAPTOP="true"; shift ;;
    --profile)    EXTRA_ARGS+=("--profile" "$2"); shift 2 ;;
    --k8s)        EXTRA_ARGS+=("--k8s" "$2");     shift 2 ;;
    --workers)    EXTRA_ARGS+=("--workers" "$2"); shift 2 ;;
    --no-desktop) EXTRA_ARGS+=("--no-desktop");   shift ;;
    --desktop)    LAPTOP_ARGS+=("--desktop");     shift ;;
    --cpus)       LAPTOP_ARGS+=("--cpus" "$2");   shift 2 ;;
    --memory)     LAPTOP_ARGS+=("--memory" "$2"); shift 2 ;;
    --disk)       LAPTOP_ARGS+=("--disk" "$2");   shift 2 ;;
    --port)       LAPTOP_ARGS+=("--port" "$2");   shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${LAPTOP}" == "true" ]]; then
  [[ -n "${REMOTE_HOST}" ]] && { echo "ERROR: --laptop and --host are mutually exclusive"; exit 1; }
  exec "${SCRIPT_DIR}/local/k16s-local" up "${EXTRA_ARGS[@]:-}" "${LAPTOP_ARGS[@]:-}"
fi

if [[ -n "${REMOTE_HOST}" ]]; then
  SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)
  [[ -n "${SSH_KEY}" ]] && SSH_OPTS+=(-i "${SSH_KEY}")

  echo "→ Uploading K16S to ${SSH_USER}@${REMOTE_HOST}:/opt/k16s ..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" "mkdir -p /opt/k16s"

  # Sync entire repo; skip build artifacts and secrets
  rsync -az --delete \
    --exclude='.git/' \
    --exclude='*.md' \
    --exclude='server/frontend/node_modules/' \
    --exclude='server/frontend/build/' \
    --exclude='server/frontend/.svelte-kit/' \
    --exclude='.env' \
    "${SCRIPT_DIR}/" \
    "${SSH_USER}@${REMOTE_HOST}:/opt/k16s/" \
    2>/dev/null \
  || tar czf - \
       -C "${SCRIPT_DIR}" \
       --exclude='.git' \
       --exclude='*.md' \
       --exclude='server/frontend/node_modules' \
       --exclude='server/frontend/build' \
       --exclude='server/frontend/.svelte-kit' \
       . \
     | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
         "cd /opt/k16s && tar xzf -"

  echo "→ Running provisioner on ${REMOTE_HOST} ..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
    "bash /opt/k16s/provision/main.sh ${EXTRA_ARGS[*]:-}"
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || { echo "Run as root or with sudo"; exit 1; }
[[ -f "${SCRIPT_DIR}/provision/main.sh" ]] || {
  echo "ERROR: provision/ directory not found. Run from the repo root."
  exit 1
}

bash "${SCRIPT_DIR}/provision/main.sh" "${EXTRA_ARGS[@]:-}"
