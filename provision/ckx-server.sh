#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "CKX exam server"

already_done "ckx-server" && { log_skip "ckx-server"; exit 0; }

mkdir -p /etc/ckx /var/lib/ckx

if ! cmd_exists etcdctl; then
  log_info "Installing etcdctl..."
  ETCD_VERSION="${CKX_ETCD_VERSION:-v3.5.17}"
  ARCH=$(dpkg --print-architecture)
  ETCD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
  curl -fsSL "${ETCD_URL}" | tar xz -C /tmp
  install /tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl /usr/local/bin/etcdctl
  rm -rf /tmp/etcd-${ETCD_VERSION}-linux-${ARCH}
  log_ok "etcdctl ${ETCD_VERSION} installed"
fi

if ! cmd_exists helm; then
  log_info "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_ok "helm installed"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -d "${REPO_ROOT}/exams" ]]; then
  mkdir -p /var/lib/ckx/exams
  cp -r "${REPO_ROOT}/exams/"* /var/lib/ckx/exams/ 2>/dev/null || true
  log_ok "Exam data copied to /var/lib/ckx/exams"
fi

# Placeholder until the Go binary is built
if ! cmd_exists ckx-server 2>/dev/null; then
  cat > /usr/local/bin/ckx-server-placeholder <<'PYSERVER'
#!/usr/bin/env python3
import http.server, socketserver, json, os

PORT = int(os.environ.get("CKX_PORT", "8080"))

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass
    def do_GET(self):
        body = json.dumps({"status": "ok", "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"CKX placeholder listening on 127.0.0.1:{PORT}", flush=True)
    httpd.serve_forever()
PYSERVER
  chmod +x /usr/local/bin/ckx-server-placeholder
fi

cat > /etc/systemd/system/ckx-server.service <<'EOF'
[Unit]
Description=CKX Exam Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/ckx
Environment=CKX_PORT=8080
Environment=KUBECONFIG=/root/.kube/config
ExecStart=/usr/local/bin/ckx-server-placeholder
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ckx-server.service
log_ok "ckx-server service started (placeholder)"

mark_done "ckx-server"
