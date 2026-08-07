#!/usr/bin/env bash
# Runs inside the kind control-plane container (docker exec), not on the
# host. Handles everything about the candidate account that's local to this
# container. Pushing the resulting key out to worker containers and writing
# their Host entries into ~/.ssh/config happens from the host side in
# k16s-lite instead — this container has no docker access to reach sibling
# node containers, unlike incus exec in the heavy mode's candidate.sh, and
# deliberately isn't given any (no Docker socket mounted in).
set -euo pipefail
source "$(dirname "$0")/../../provision/lib.sh"

log_step "Candidate user (lightweight)"

# k16s-lite's cmd_up re-runs the whole provisioning pipeline whenever it's
# invoked against a cluster that already exists (see the comment in cmd_up
# for why — resuming an interrupted `up` needs this). Without this guard
# that regenerated the candidate password and re-ran ssh-keygen against an
# existing key every single re-run, confirmed live (ssh-keygen prompted
# "Overwrite (y/n)?" against a non-interactive docker exec and got skipped
# by luck, not by design).
already_done "candidate-lite" && { log_skip "candidate user"; exit 0; }

CANDIDATE_PASS="${K16S_CANDIDATE_PASS:-k16s-$(openssl rand -hex 4)}"

# The kind node image is a minimal Debian base — neither sudo nor even the
# OpenSSH client (ssh-keygen) is installed, confirmed live (no /usr/bin/sudo,
# no /etc/sudoers.d, "ssh-keygen: command not found"). Neither is needed for
# kubeadm/kubelet/containerd to run, so the image skips them.
if ! command -v sudo &>/dev/null || ! command -v ssh-keygen &>/dev/null; then
  apt-get update -q
  apt-get install -y --no-install-recommends sudo openssh-client
fi

if ! id candidate &>/dev/null; then
  useradd -m -s /bin/bash candidate
fi

echo "candidate:${CANDIDATE_PASS}" | chpasswd
mkdir -p /etc/k16s
echo "${CANDIDATE_PASS}" > /etc/k16s/candidate-password
chmod 600 /etc/k16s/candidate-password

mkdir -p /home/candidate/.kube
cp /etc/kubernetes/admin.conf /home/candidate/.kube/config
chown -R candidate:candidate /home/candidate/.kube

# The kind node image bakes KUBECONFIG=/etc/kubernetes/admin.conf into the
# container's own environment (confirmed live: present for every `docker
# exec`, even for candidate, before any shell dotfile runs) — that file is
# root-only (0600), so it silently wins over candidate's own copy above and
# every kubectl command fails with "permission denied", not a config error.
# /etc/profile.d is sourced by every login shell regardless of a user's own
# ~/.profile/~/.bashrc chain (unlike heavy mode, where nothing pre-sets
# KUBECONFIG at the image level, so .bashrc's export was always enough) —
# confirmed this is what ttyd's `login -f candidate` actually goes through.
echo "export KUBECONFIG=/home/candidate/.kube/config" > /etc/profile.d/k16s-kubeconfig.sh

cat > /etc/sudoers.d/candidate <<'EOF'
candidate ALL=(root) NOPASSWD: /usr/bin/kubectl, /usr/sbin/etcdctl, /usr/local/bin/etcdctl
EOF
chmod 440 /etc/sudoers.d/candidate

su - candidate -c 'ssh-keygen -t ed25519 -N "" -f /home/candidate/.ssh/id_ed25519 -C candidate@controlplane' \
  2>/dev/null || true

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
chown -R candidate:candidate /home/candidate/.ssh

mark_done "candidate-lite"
log_ok "Candidate environment configured (password: ${CANDIDATE_PASS})"
