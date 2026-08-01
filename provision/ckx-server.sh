#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "CKX exam server"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

# ── Tool installation (idempotent) ────────────────────────────────────────

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

if ! cmd_exists go; then
  log_info "Installing Go..."
  GO_VERSION="1.23.8"
  ARCH=$(dpkg --print-architecture | sed 's/amd64/amd64/; s/arm64/arm64/')
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar xz -C /usr/local
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  log_ok "Go ${GO_VERSION} installed"
fi

if ! cmd_exists node; then
  log_info "Installing Node.js (for frontend build)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt_install nodejs
  log_ok "Node.js installed"
fi

# ── Exam data ─────────────────────────────────────────────────────────────

mkdir -p /var/lib/ckx/exams

if [[ -d "${REPO_ROOT}/exams" ]]; then
  cp -r "${REPO_ROOT}/exams/"* /var/lib/ckx/exams/
  chmod -R +x /var/lib/ckx/exams/*/scripts 2>/dev/null || true
  log_ok "Exam data synced to /var/lib/ckx/exams"
fi

# ── Go binary ─────────────────────────────────────────────────────────────

if [[ -d "${REPO_ROOT}/server" ]]; then
  log_info "Building ckx-server..."
  pushd "${REPO_ROOT}/server" > /dev/null

  if [[ -d frontend/src ]]; then
    log_info "Building frontend..."
    npm install --silent
    npm run build --silent
    log_ok "Frontend built"
  fi

  go mod tidy
  go build -o /usr/local/bin/ckx-server .
  popd > /dev/null
  log_ok "ckx-server binary installed"
fi

# ── Systemd service ───────────────────────────────────────────────────────

BINARY=/usr/local/bin/ckx-server
if [[ ! -f "${BINARY}" ]]; then
  # Fallback placeholder if source was not uploaded
  cat > "${BINARY}" <<'PYSERVER'
#!/usr/bin/env python3
import http.server, socketserver, json, os
PORT = int(os.environ.get("CKX_PORT", "8080"))
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        b = json.dumps({"status":"ok","note":"placeholder"}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",len(b)); self.end_headers(); self.wfile.write(b)
with socketserver.TCPServer(("127.0.0.1",PORT),H) as h: print(f"placeholder on {PORT}",flush=True); h.serve_forever()
PYSERVER
  chmod +x "${BINARY}"
  log_ok "Placeholder server installed"
fi

cat > /etc/systemd/system/ckx-server.service <<EOF
[Unit]
Description=CKX Exam Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/ckx
Environment=CKX_PORT=8080
Environment=CKX_DB=/var/lib/ckx/ckx.db
Environment=CKX_EXAM_DIR=/var/lib/ckx/exams
Environment=KUBECONFIG=/etc/kubernetes/admin.conf
ExecStart=${BINARY}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ckx-server
systemctl restart ckx-server
log_ok "ckx-server service started"
