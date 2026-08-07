#!/usr/bin/env bash
# K16S — Uninstaller. Mirrors install.sh's modes.
# Usage:
#   On the VM directly:  bash uninstall.sh [--yes] [--dry-run]
#   Targeting a remote:  bash uninstall.sh --host 1.2.3.4 [--key ~/.ssh/id_ed25519] [--yes] [--dry-run]
#   On your laptop:      bash uninstall.sh --laptop [--yes]
#   Lightweight (kind):  bash uninstall.sh --lightweight [--yes]
set -euo pipefail

REMOTE_HOST=""
SSH_KEY=""
SSH_USER="root"
LAPTOP="false"
LIGHTWEIGHT="false"
TEARDOWN_ARGS=()   # bare-host teardown.sh — supports --yes and --dry-run
DESTROY_ARGS=()    # k16s-local/k16s-lite destroy — --yes only, no dry-run:
                    # deleting a VM/kind cluster is already one atomic,
                    # unambiguous action with nothing partial to preview.

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)        REMOTE_HOST="$2"; shift 2 ;;
    --key)         SSH_KEY="$2";     shift 2 ;;
    --user)        SSH_USER="$2";    shift 2 ;;
    --laptop)      LAPTOP="true";    shift ;;
    --lightweight) LIGHTWEIGHT="true"; shift ;;
    --yes|-y)   TEARDOWN_ARGS+=("--yes"); DESTROY_ARGS+=("--yes"); shift ;;
    --dry-run)  TEARDOWN_ARGS+=("--dry-run"); shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${LAPTOP}" == "true" && "${LIGHTWEIGHT}" == "true" ]]; then
  echo "ERROR: --laptop and --lightweight are mutually exclusive"; exit 1
fi

if [[ "${LAPTOP}" == "true" ]]; then
  [[ -n "${REMOTE_HOST}" ]] && { echo "ERROR: --laptop and --host are mutually exclusive"; exit 1; }
  exec "${SCRIPT_DIR}/local/k16s-local" destroy "${DESTROY_ARGS[@]}"
fi

if [[ "${LIGHTWEIGHT}" == "true" ]]; then
  [[ -n "${REMOTE_HOST}" ]] && { echo "ERROR: --lightweight and --host are mutually exclusive"; exit 1; }
  exec "${SCRIPT_DIR}/lightweight/k16s-lite" destroy "${DESTROY_ARGS[@]}"
fi

if [[ -n "${REMOTE_HOST}" ]]; then
  SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)
  # See install.sh for why IdentitiesOnly is paired with -i here.
  [[ -n "${SSH_KEY}" ]] && SSH_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)

  echo "→ Uploading teardown scripts to ${SSH_USER}@${REMOTE_HOST}:/opt/k16s ..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" "mkdir -p /opt/k16s"

  # Only provision/ is needed on the remote side — teardown.sh + lib.sh are
  # self-contained and don't touch exams/ or server/.
  rsync -az \
    "${SCRIPT_DIR}/provision/" \
    "${SSH_USER}@${REMOTE_HOST}:/opt/k16s/provision/" \
    2>/dev/null \
  || tar czf - -C "${SCRIPT_DIR}" provision \
     | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
         "cd /opt/k16s && tar xzf -"

  echo "→ Running teardown on ${REMOTE_HOST} ..."
  ssh -t "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" \
    "bash /opt/k16s/provision/teardown.sh ${TEARDOWN_ARGS[*]:-}"
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || { echo "Run as root or with sudo"; exit 1; }
[[ -f "${SCRIPT_DIR}/provision/teardown.sh" ]] || {
  echo "ERROR: provision/teardown.sh not found. Run from the repo root."
  exit 1
}

bash "${SCRIPT_DIR}/provision/teardown.sh" "${TEARDOWN_ARGS[@]}"
