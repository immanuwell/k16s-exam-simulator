#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-pki

echo "Environment ready — generate a 3072-bit RSA key at /opt/cks3-pki/user.key"
