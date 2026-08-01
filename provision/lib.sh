#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'
  BLU='\033[0;34m'; CYN='\033[0;36m'; DIM='\033[2m'; RST='\033[0m'
else
  RED=''; YEL=''; GRN=''; BLU=''; CYN=''; DIM=''; RST=''
fi

log_step() { echo -e "\n${BLU}▶${RST} ${1}"; }
log_ok()   { echo -e "  ${GRN}✓${RST} ${1}"; }
log_skip() { echo -e "  ${DIM}↷ ${1} (already done)${RST}"; }
log_warn() { echo -e "  ${YEL}⚠${RST} ${1}"; }
log_info() { echo -e "  ${CYN}·${RST} ${1}"; }

die() {
  echo -e "\n${RED}✗ FATAL:${RST} ${1}" >&2
  echo -e "${DIM}  at ${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}${RST}" >&2
  exit 1
}

MARKER_DIR="/var/lib/ckx/markers"

already_done() { [[ -f "${MARKER_DIR}/${1}.done" ]]; }

mark_done() {
  mkdir -p "$MARKER_DIR"
  touch "${MARKER_DIR}/${1}.done"
}

wait_for() {
  local desc="$1" timeout="$2" cmd="${@:3}"
  local elapsed=0
  while ! eval "$cmd" &>/dev/null; do
    sleep 2; elapsed=$((elapsed+2))
    [[ $elapsed -ge $timeout ]] && die "Timed out waiting for: $desc"
    echo -n "."
  done
  echo ""
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

cmd_exists() { command -v "$1" &>/dev/null; }
