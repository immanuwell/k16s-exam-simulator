#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Kernel modules & sysctl"

already_done "kernel" && { log_skip "kernel modules"; exit 0; }

cat > /etc/modules-load.d/k16s-k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
log_ok "Loaded: overlay, br_netfilter"

cat > /etc/sysctl.d/99-k16s-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system -q
log_ok "sysctl applied"

mark_done "kernel"
log_ok "Kernel configuration complete"
