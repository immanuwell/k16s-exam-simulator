#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki
openssl genrsa -out /opt/cks2-pki/ca2.key 4096 2>/dev/null

echo "CA key ready at /opt/cks2-pki/ca2.key — create a self-signed CA certificate at /opt/cks2-pki/ca2.crt"
