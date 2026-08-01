#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-pki

openssl genrsa -out /opt/cks3-pki/alice.key 2048 2>/dev/null
chmod 600 /opt/cks3-pki/alice.key

echo "Private key ready at /opt/cks3-pki/alice.key — create a CSR with CN=alice and O=dev,O=ops"
