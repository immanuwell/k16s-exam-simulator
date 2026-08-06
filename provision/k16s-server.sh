#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "K16S exam server"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
BINARY=/usr/local/bin/k16s-server

# ── Tool installation (idempotent) ────────────────────────────────────────

if ! cmd_exists etcdctl; then
  log_info "Installing etcdctl..."
  ETCD_VERSION="${K16S_ETCD_VERSION:-v3.5.17}"
  ARCH=$(dpkg --print-architecture)
  ETCD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
  curl -fsSL "${ETCD_URL}" | tar xz -C /tmp
  install "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
  rm -rf "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}"
  log_ok "etcdctl ${ETCD_VERSION} installed"
fi

if ! cmd_exists helm; then
  log_info "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_ok "helm installed"
fi

# ── Exam data ─────────────────────────────────────────────────────────────

mkdir -p /var/lib/k16s/exams

if [[ -d "${REPO_ROOT}/exams" ]]; then
  cp -r "${REPO_ROOT}/exams/"* /var/lib/k16s/exams/
  find /var/lib/k16s/exams -name "*.sh" -exec chmod +x {} \;
  log_ok "Exam data synced to /var/lib/k16s/exams"
fi

# ── Binary ────────────────────────────────────────────────────────────────
# Long-term: download pre-built binary from GitHub Releases (no Go/Node on VM).
# Until CI is set up, build from source if the binary isn't already present.

if [[ -f "${BINARY}" ]]; then
  log_skip "k16s-server binary already exists (delete to force rebuild)"

elif [[ -d "${REPO_ROOT}/server" ]]; then
  log_info "Building k16s-server from source..."

  if ! cmd_exists go; then
    log_info "Installing Go..."
    GO_VERSION="1.23.8"
    ARCH=$(dpkg --print-architecture)
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar xz -C /usr/local
    ln -sf /usr/local/go/bin/go    /usr/local/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    log_ok "Go ${GO_VERSION} installed"
  fi

  # Test for npm as well as node, and reject a too-old node. On Ubuntu the
  # desktop step pulls in novnc, which depends on the distro `nodejs` package
  # (18.x, and no npm — Ubuntu ships npm separately). A node-only test then
  # skips this block and the frontend build dies on "npm: command not found".
  # The frontend needs Vite 8, which requires node >= 20.19.
  NODE_MAJOR=0
  cmd_exists node && NODE_MAJOR=$(node --version | sed 's/^v\([0-9]*\).*/\1/')
  if ! cmd_exists node || ! cmd_exists npm || [[ "${NODE_MAJOR}" -lt 20 ]]; then
    log_info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt_install nodejs
    log_ok "Node.js $(node --version) / npm $(npm --version) installed"
  fi

  pushd "${REPO_ROOT}/server" > /dev/null
  if [[ -d frontend/src ]]; then
    (cd frontend && npm install --silent && npm run build --silent)
    log_ok "Frontend built"
  fi
  go mod tidy
  go build -o "${BINARY}" .
  popd > /dev/null
  log_ok "k16s-server built and installed"

else
  # Fallback placeholder — serves a minimal JSON response until binary is deployed
  log_warn "No source found at ${REPO_ROOT}/server — installing placeholder"
  cat > "${BINARY}" <<'PYSERVER'
#!/usr/bin/env python3
import http.server, socketserver, json, os
PORT = int(os.environ.get("K16S_PORT", "8080"))
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        b = json.dumps({"status": "ok", "note": "placeholder — deploy k16s-server binary"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(b))
        self.end_headers()
        self.wfile.write(b)
with socketserver.TCPServer(("127.0.0.1", PORT), H) as h:
    print(f"K16S placeholder on :{PORT}", flush=True)
    h.serve_forever()
PYSERVER
  chmod +x "${BINARY}"
fi

# ── Systemd service ───────────────────────────────────────────────────────

cat > /etc/systemd/system/k16s-server.service <<EOF
[Unit]
Description=K16S Exam Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/k16s
Environment=K16S_PORT=8080
Environment=K16S_DB=/var/lib/k16s/k16s.db
Environment=K16S_EXAM_DIR=/var/lib/k16s/exams
Environment=KUBECONFIG=/etc/kubernetes/admin.conf
ExecStart=${BINARY}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable k16s-server
systemctl restart k16s-server
log_ok "k16s-server service started"
