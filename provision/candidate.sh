#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Candidate user environment"

already_done "candidate" && { log_skip "candidate user"; exit 0; }

WORKER_COUNT="${CKX_WORKER_COUNT:-2}"
NET_BASE="${CKX_NET_BASE:-10.10.0}"
NODE_IP_START=11
CANDIDATE_PASS="${CKX_CANDIDATE_PASS:-ckx-$(openssl rand -hex 4)}"

if ! id candidate &>/dev/null; then
  useradd -m -s /bin/bash candidate
  log_ok "User 'candidate' created"
fi

echo "candidate:${CANDIDATE_PASS}" | chpasswd
echo "${CANDIDATE_PASS}" > /etc/ckx/candidate-password
chmod 600 /etc/ckx/candidate-password
log_info "Candidate password: ${CANDIDATE_PASS}"

mkdir -p /home/candidate/.kube
cp /root/.kube/config /home/candidate/.kube/config
chown -R candidate:candidate /home/candidate/.kube
log_ok "kubeconfig copied for candidate"

# Limited sudo — no shell escalation
cat > /etc/sudoers.d/candidate <<'EOF'
candidate ALL=(root) NOPASSWD: /usr/bin/kubectl, /usr/sbin/etcdctl, /usr/local/bin/etcdctl
EOF
chmod 440 /etc/sudoers.d/candidate

su - candidate -c 'ssh-keygen -t ed25519 -N "" -f /home/candidate/.ssh/id_ed25519 -C candidate@controlplane' \
  2>/dev/null || true
CANDIDATE_PUBKEY=$(cat /home/candidate/.ssh/id_ed25519.pub)

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  incus exec "${NAME}" -- bash -c "
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo '${CANDIDATE_PUBKEY}' >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
  "
  log_ok "Candidate SSH key installed on ${NAME}"
done

mkdir -p /home/candidate/.ssh
cat > /home/candidate/.ssh/config <<EOF
Host controlplane
  HostName 127.0.0.1
  User root
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

EOF

for i in $(seq 1 "${WORKER_COUNT}"); do
  NAME="node0${i}"
  NODE_IP="${NET_BASE}.$((NODE_IP_START + i - 1))"
  cat >> /home/candidate/.ssh/config <<EOF
Host ${NAME}
  HostName ${NODE_IP}
  User root
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

EOF
done
chmod 600 /home/candidate/.ssh/config
chown -R candidate:candidate /home/candidate/.ssh

cat >> /home/candidate/.bashrc <<'BASHRC'

export KUBECONFIG=/home/candidate/.kube/config

source /usr/share/bash-completion/bash_completion 2>/dev/null || true
source <(kubectl completion bash) 2>/dev/null || true
alias k=kubectl
complete -F __start_kubectl k 2>/dev/null || true

export EDITOR=vim
alias vi=vim
export ETCDCTL_API=3

alias kn='kubectl config set-context --current --namespace'
alias kgp='kubectl get pods -o wide'
alias kd='kubectl describe'
alias krm='kubectl delete'

BASHRC

cat > /home/candidate/.vimrc <<'EOF'
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set nu
EOF
chown candidate:candidate /home/candidate/.vimrc

cat > /home/candidate/.tmux.conf <<'EOF'
set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
bind | split-window -h
bind - split-window -v
EOF
chown candidate:candidate /home/candidate/.tmux.conf

touch /home/candidate/.hushlogin
chown candidate:candidate /home/candidate/.hushlogin

mark_done "candidate"
log_ok "Candidate environment configured (password: ${CANDIDATE_PASS})"
