#!/usr/bin/env bash
# K16S — Self-Hosted Kubernetes Exam Platform
# Usage:
#   On the VM directly:  bash install.sh [--profile cka] [--k8s 1.33] [--workers 1]
#   Targeting a remote:  bash install.sh --host 1.2.3.4 [--key ~/.ssh/id_ed25519] [--tunnel|--no-tunnel] [--port 8080]
#   On your laptop:      bash install.sh --laptop [--profile cka] [--cpus 4] [--memory 8]
#   Lightweight (kind):  bash install.sh --lightweight [--profile cka] [--workers 1]
#
# --host targets get nginx bound to 127.0.0.1 (only reachable via the SSH
# tunnel this script opens automatically) whenever the target IP is public —
# private/LAN IPs are unaffected, since there's nothing to expose there in
# the first place. --tunnel/--no-tunnel override the auto-detection.
set -euo pipefail

REMOTE_HOST=""
SSH_KEY=""
SSH_USER="root"
LAPTOP="false"
LIGHTWEIGHT="false"
TUNNEL_MODE="auto"   # auto | force | never — see --tunnel/--no-tunnel below
TUNNEL_PORT="8080"
EXTRA_ARGS=()
LAPTOP_ARGS=()
LITE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    REMOTE_HOST="$2";  shift 2 ;;
    --key)     SSH_KEY="$2";      shift 2 ;;
    --user)    SSH_USER="$2";     shift 2 ;;
    --laptop)      LAPTOP="true"; shift ;;
    --lightweight) LIGHTWEIGHT="true"; shift ;;
    --tunnel)      TUNNEL_MODE="force"; shift ;;
    --no-tunnel)   TUNNEL_MODE="never"; shift ;;
    --profile)    EXTRA_ARGS+=("--profile" "$2"); LITE_ARGS+=("--profile" "$2"); shift 2 ;;
    --k8s)        EXTRA_ARGS+=("--k8s" "$2");     shift 2 ;;
    --workers)    EXTRA_ARGS+=("--workers" "$2"); LITE_ARGS+=("--workers" "$2"); shift 2 ;;
    --no-desktop) EXTRA_ARGS+=("--no-desktop");   shift ;;
    --desktop)    LAPTOP_ARGS+=("--desktop");     shift ;;
    --cpus)       LAPTOP_ARGS+=("--cpus" "$2");   shift 2 ;;
    --memory)     LAPTOP_ARGS+=("--memory" "$2"); shift 2 ;;
    --disk)       LAPTOP_ARGS+=("--disk" "$2");   shift 2 ;;
    --port)       LAPTOP_ARGS+=("--port" "$2"); LITE_ARGS+=("--port" "$2"); TUNNEL_PORT="$2"; shift 2 ;;
    --k8s-image)  LITE_ARGS+=("--k8s-image" "$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Private vs. public IP classification (only used for --host) ──────────

resolve_ipv4() {
  local host="$1"
  # Already a literal dotted-quad — the overwhelmingly common case for
  # --host — needs no resolution at all.
  if [[ "${host}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "${host}"
    return 0
  fi
  # Hostname: try whatever resolver this OS actually has. getent is
  # Linux-only (glibc); python3 and ping are the portable fallbacks for
  # running install.sh from macOS against a remote host — ping resolves the
  # name before it ever sends a packet, on both GNU and BSD/macOS ping, so
  # it works even when the host doesn't answer ICMP. The ping path is
  # unverified on actual macOS as of writing; the literal-IP and getent
  # paths are what's exercised in practice.
  #
  # Every fallback below is deliberately guarded with `|| true`: a lookup
  # failure here must never abort install.sh under set -e. Confirmed live
  # that it otherwise can — an unresolvable hostname reached this function,
  # its resolver pipeline failed exactly as intended, and install.sh exited
  # silently with no output at all, which is a much worse failure mode than
  # the "assume public, use the tunnel" fallback this function exists for.
  if command -v getent &>/dev/null; then
    local r; r=$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1; exit}') || true
    [[ -n "${r}" ]] && { echo "${r}"; return 0; }
  fi
  if command -v python3 &>/dev/null; then
    local r; r=$(python3 -c "import socket; print(socket.gethostbyname('${host}'))" 2>/dev/null) || true
    [[ -n "${r}" ]] && { echo "${r}"; return 0; }
  fi
  ping -c1 "${host}" 2>/dev/null | head -1 | sed -n 's/.*(\([0-9.]*\)).*/\1/p' || true
}

# RFC1918 + loopback + link-local + CGNAT (RFC6598) — ranges that are never
# reachable from the public internet, so binding nginx to all interfaces
# there is exactly as safe as it's always been.
is_private_ipv4() {
  local ip="$1"
  [[ "${ip}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}"
  [[ "${o1}" -eq 10 ]] && return 0
  [[ "${o1}" -eq 172 && "${o2}" -ge 16 && "${o2}" -le 31 ]] && return 0
  [[ "${o1}" -eq 192 && "${o2}" -eq 168 ]] && return 0
  [[ "${o1}" -eq 127 ]] && return 0
  [[ "${o1}" -eq 169 && "${o2}" -eq 254 ]] && return 0
  [[ "${o1}" -eq 100 && "${o2}" -ge 64 && "${o2}" -le 127 ]] && return 0
  return 1
}

if [[ "${LAPTOP}" == "true" && "${LIGHTWEIGHT}" == "true" ]]; then
  echo "ERROR: --laptop and --lightweight are mutually exclusive"; exit 1
fi

if [[ "${LAPTOP}" == "true" ]]; then
  [[ -n "${REMOTE_HOST}" ]] && { echo "ERROR: --laptop and --host are mutually exclusive"; exit 1; }
  exec "${SCRIPT_DIR}/local/k16s-local" up "${EXTRA_ARGS[@]}" "${LAPTOP_ARGS[@]}"
fi

if [[ "${LIGHTWEIGHT}" == "true" ]]; then
  [[ -n "${REMOTE_HOST}" ]] && { echo "ERROR: --lightweight and --host are mutually exclusive"; exit 1; }
  exec "${SCRIPT_DIR}/lightweight/k16s-lite" up "${LITE_ARGS[@]}"
fi

if [[ -n "${REMOTE_HOST}" ]]; then
  SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10)
  # IdentitiesOnly matters here: without it, an agent loaded with other keys
  # gets tried first and can exhaust the server's MaxAuthTries before this
  # key is ever offered — --key would silently never be used.
  [[ -n "${SSH_KEY}" ]] && SSH_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)

  TUNNEL_REASON=""
  case "${TUNNEL_MODE}" in
    force)
      NEED_TUNNEL="true"
      TUNNEL_REASON="--tunnel was passed explicitly"
      ;;
    never)
      NEED_TUNNEL="false"
      TUNNEL_REASON="--no-tunnel was passed explicitly"
      ;;
    *)
      RESOLVED_IP="$(resolve_ipv4 "${REMOTE_HOST}")"
      if [[ -n "${RESOLVED_IP}" ]] && is_private_ipv4 "${RESOLVED_IP}"; then
        NEED_TUNNEL="false"
        TUNNEL_REASON="${REMOTE_HOST} resolved to ${RESOLVED_IP}, a private/LAN address"
      elif [[ -n "${RESOLVED_IP}" ]]; then
        NEED_TUNNEL="true"
        TUNNEL_REASON="${REMOTE_HOST} resolved to ${RESOLVED_IP}, a public address"
      else
        # Classification failed outright (unresolvable hostname, IPv6, no
        # resolver available) — default to the safe side rather than
        # assume it's fine to expose.
        NEED_TUNNEL="true"
        TUNNEL_REASON="couldn't determine whether ${REMOTE_HOST} is private or public"
      fi
      ;;
  esac

  if [[ "${NEED_TUNNEL}" == "true" ]]; then
    EXTRA_ARGS+=("--bind-loopback")
    echo "→ ${TUNNEL_REASON} — nginx will bind 127.0.0.1 only, reachable via an SSH tunnel this script opens automatically. Pass --no-tunnel to skip this."
  else
    echo "→ ${TUNNEL_REASON} — binding nginx to all interfaces, same as before. Pass --tunnel to force the loopback+SSH-tunnel path anyway."
  fi

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

  if [[ "${NEED_TUNNEL}" == "true" ]]; then
    TUNNEL_ARGS=(--port "${TUNNEL_PORT}" --user "${SSH_USER}")
    [[ -n "${SSH_KEY}" ]] && TUNNEL_ARGS+=(--key "${SSH_KEY}")
    "${SCRIPT_DIR}/k16s-tunnel" up "${REMOTE_HOST}" "${TUNNEL_ARGS[@]}"
  fi
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || { echo "Run as root or with sudo"; exit 1; }
[[ -f "${SCRIPT_DIR}/provision/main.sh" ]] || {
  echo "ERROR: provision/ directory not found. Run from the repo root."
  exit 1
}

bash "${SCRIPT_DIR}/provision/main.sh" "${EXTRA_ARGS[@]}"
