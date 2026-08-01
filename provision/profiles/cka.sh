#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

log_step "CKA profile extras"

ETCD_CA="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

if [[ -f "${ETCD_CA}" ]]; then
  cat >> /home/candidate/.bashrc <<EOF

export ETCDCTL_CACERT=${ETCD_CA}
export ETCDCTL_CERT=${ETCD_CERT}
export ETCDCTL_KEY=${ETCD_KEY}
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
EOF
  log_ok "etcdctl environment variables set for candidate"
fi

log_ok "CKA profile configured"
