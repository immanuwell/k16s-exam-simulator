#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki

openssl req -newkey rsa:2048 -nodes \
  -keyout /opt/cks2-pki/verify-ca.key \
  -x509 -days 3650 \
  -out /opt/cks2-pki/verify-ca.crt \
  -subj "/CN=test-ca" 2>/dev/null

openssl req -newkey rsa:2048 -nodes \
  -keyout /opt/cks2-pki/verify.key \
  -new -out /tmp/verify-setup.csr \
  -subj "/CN=verify-service" 2>/dev/null

openssl x509 -req \
  -in /tmp/verify-setup.csr \
  -CA /opt/cks2-pki/verify-ca.crt \
  -CAkey /opt/cks2-pki/verify-ca.key \
  -CAcreateserial \
  -out /opt/cks2-pki/verify.crt \
  -days 365 2>/dev/null

rm -f /tmp/verify-setup.csr

echo "verify.crt and verify-ca.crt ready — run openssl verify and save result to /opt/cks2-pki/verify-result.txt"
