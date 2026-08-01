#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "ttyd (web terminal)"

already_done "ttyd" && { log_skip "ttyd"; exit 0; }

TTYD_VERSION="${K16S_TTYD_VERSION:-1.7.7}"
ARCH=$(dpkg --print-architecture)

case "${ARCH}" in
  amd64)  TTYD_ARCH="x86_64" ;;
  arm64)  TTYD_ARCH="aarch64" ;;
  *)      die "Unsupported architecture for ttyd: ${ARCH}" ;;
esac

log_info "Downloading ttyd ${TTYD_VERSION} (${TTYD_ARCH})..."
curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
  -o /usr/local/bin/ttyd
chmod +x /usr/local/bin/ttyd
log_ok "ttyd installed at /usr/local/bin/ttyd"

cat > /etc/systemd/system/k16s-terminal.service <<'EOF'
[Unit]
Description=K16S Web Terminal (ttyd)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ttyd \
  --port 7681 \
  --interface 127.0.0.1 \
  --writable \
  login -f candidate
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now k16s-terminal.service
log_ok "k16s-terminal service started on 127.0.0.1:7681"

mark_done "ttyd"
