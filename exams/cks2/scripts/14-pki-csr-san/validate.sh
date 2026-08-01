#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks2-pki/svc.csr ]]; then
  echo "FAIL: /opt/cks2-pki/svc.csr not found"
  exit 1
fi

if ! openssl req -in /opt/cks2-pki/svc.csr -noout 2>/dev/null; then
  echo "FAIL: /opt/cks2-pki/svc.csr is not a valid CSR"
  exit 1
fi

CSR_TEXT=$(openssl req -in /opt/cks2-pki/svc.csr -noout -text 2>/dev/null)

if ! echo "$CSR_TEXT" | grep -q "svc.internal"; then
  echo "FAIL: CSR does not contain SAN DNS:svc.internal"
  exit 1
fi

if ! echo "$CSR_TEXT" | grep -q "svc.cluster.local"; then
  echo "FAIL: CSR does not contain SAN DNS:svc.cluster.local"
  exit 1
fi

echo "PASS: svc.csr contains SANs svc.internal and svc.cluster.local"
