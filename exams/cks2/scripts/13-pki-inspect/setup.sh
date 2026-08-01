#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki

openssl req -newkey rsa:2048 -nodes \
  -keyout /opt/cks2-pki/server.key \
  -x509 -days 365 \
  -out /opt/cks2-pki/server.crt \
  -subj "/CN=api.example.com/O=platform" \
  -addext "subjectAltName=DNS:api.example.com,DNS:api-internal.example.com" \
  2>/dev/null

echo "Certificate ready at /opt/cks2-pki/server.crt — inspect it and save full details to /opt/cks2-pki/server-crt.txt"
