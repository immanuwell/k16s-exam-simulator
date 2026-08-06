#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "SSH server on worker nodes"

already_done "node-ssh" && { log_skip "worker sshd"; exit 0; }

WORKER_COUNT="${K16S_WORKER_COUNT:-1}"

# The Incus base image (debian/12) ships the OpenSSH *client* only — /etc/ssh
# holds ssh_config and no sshd. candidate.sh installs the candidate's public key
# into /root/.ssh/authorized_keys on every worker, but with nothing listening on
# port 22 the exam's `ssh node01` just gets ECONNREFUSED. Install the server.

install_sshd() {
  local NAME="$1"

  if incus exec "${NAME}" -- test -x /usr/sbin/sshd 2>/dev/null; then
    log_info "  ${NAME}: openssh-server already installed"
  else
    incus exec "${NAME}" -- bash -c '
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -q
      apt-get install -y --no-install-recommends openssh-server
    '
    log_ok "  ${NAME}: openssh-server installed"
  fi

  # Root login by key only. sshd honours the *first* value it sees for a
  # keyword, and Debian puts the Include at the top of sshd_config, so a drop-in
  # beats the vendor defaults. Images without the Include get the same settings
  # written straight into sshd_config instead. Both branches clear their target
  # before writing, so a re-run neither stacks duplicate blocks nor leaves a
  # stale earlier occurrence shadowing the new one.
  incus exec "${NAME}" -- bash -c '
    KEYWORDS="PermitRootLogin|PubkeyAuthentication|PasswordAuthentication"
    if grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config; then
      mkdir -p /etc/ssh/sshd_config.d
      CONF=/etc/ssh/sshd_config.d/10-k16s.conf
      : > "${CONF}"
    else
      sed -i -E "/^[[:space:]]*(${KEYWORDS})[[:space:]]/d" /etc/ssh/sshd_config
      CONF=/etc/ssh/sshd_config
    fi
    cat >> "${CONF}" <<EOF
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
EOF
    systemctl enable ssh
    systemctl restart ssh
  '
}

wait_for_sshd() {
  local NAME="$1"

  for _ in $(seq 1 15); do
    if incus exec "${NAME}" -- ss -lnt 2>/dev/null | grep -q ':22 '; then
      log_ok "  ${NAME}: sshd listening on :22"
      return 0
    fi
    sleep 1
  done
  die "sshd did not start on ${NAME} — check 'incus exec ${NAME} -- journalctl -u ssh'"
}

log_info "Installing sshd on ${WORKER_COUNT} worker node(s) in parallel..."
PIDS=()
for i in $(seq 1 "${WORKER_COUNT}"); do
  install_sshd "node0${i}" > "/var/log/k16s-node0${i}-sshd.log" 2>&1 &
  PIDS+=($!)
done

FAILED=0
for i in $(seq 1 "${WORKER_COUNT}"); do
  if wait "${PIDS[$((i-1))]}"; then
    log_ok "node0${i} sshd installed"
  else
    log_warn "node0${i} sshd FAILED — see /var/log/k16s-node0${i}-sshd.log"
    FAILED=$((FAILED + 1))
  fi
done
[[ "${FAILED}" -eq 0 ]] || die "${FAILED} worker node(s) failed sshd setup"

for i in $(seq 1 "${WORKER_COUNT}"); do
  wait_for_sshd "node0${i}"
done

mark_done "node-ssh"
log_ok "Worker nodes reachable over SSH"
