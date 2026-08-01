#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki

openssl genrsa -out /opt/cks2-pki/svc.key 2048 2>/dev/null

cat > /opt/cks2-pki/svc-csr.conf <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = svc.internal
O = platform

[v3_req]
subjectAltName = DNS:svc.internal,DNS:svc.cluster.local,IP:10.96.0.1
EOF

echo "Key and config ready — create /opt/cks2-pki/svc.csr using svc-csr.conf"
