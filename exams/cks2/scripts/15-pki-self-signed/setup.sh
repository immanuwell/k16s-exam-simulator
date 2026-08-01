#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks2-pki
openssl genrsa -out /opt/cks2-pki/self.key 2048 2>/dev/null

echo "Key ready at /opt/cks2-pki/self.key — create a self-signed certificate at /opt/cks2-pki/self.crt"
