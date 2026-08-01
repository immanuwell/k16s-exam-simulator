#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki

openssl req -newkey rsa:2048 -nodes \
  -keyout /tmp/b64-tmp.key \
  -x509 -days 500 \
  -out /tmp/b64-tmp.crt \
  -subj "/CN=embedded-ca" 2>/dev/null

base64 -w 0 /tmp/b64-tmp.crt > /opt/cks2-pki/embedded-ca.b64
rm -f /tmp/b64-tmp.key /tmp/b64-tmp.crt

echo "Base64-encoded certificate ready at /opt/cks2-pki/embedded-ca.b64 — decode and extract validity dates"
