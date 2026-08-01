#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks-pki

# Create CA
if [[ ! -f /opt/cks-pki/ca.key ]]; then
  openssl genrsa -out /opt/cks-pki/ca.key 2048
  openssl req -new -x509 -key /opt/cks-pki/ca.key \
    -out /opt/cks-pki/ca.crt -days 3650 \
    -subj '/CN=cks-ca/O=CKX'
  chmod 600 /opt/cks-pki/ca.key
fi

# Create app.key + app.csr
if [[ ! -f /opt/cks-pki/app.csr ]]; then
  openssl genrsa -out /opt/cks-pki/app.key 2048
  openssl req -new -key /opt/cks-pki/app.key \
    -out /opt/cks-pki/app.csr \
    -subj '/CN=app.svc/O=platform'
fi

echo "CA and CSR ready in /opt/cks-pki/ — sign app.csr with ca.crt/ca.key to produce app.crt"
