#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks-pki

# Generate alice's private key for the student to use
if [[ ! -f /opt/cks-pki/alice.key ]]; then
  openssl genrsa -out /opt/cks-pki/alice.key 2048
  chmod 600 /opt/cks-pki/alice.key
fi

echo "Private key ready at /opt/cks-pki/alice.key — create alice.csr from it"
