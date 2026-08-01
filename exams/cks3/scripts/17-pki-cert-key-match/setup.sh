#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-pki

# Generate a matching cert+key pair
openssl genrsa -out /opt/cks3-pki/real.key 2048 2>/dev/null
openssl req -new -x509 -key /opt/cks3-pki/real.key \
  -out /opt/cks3-pki/real.crt -days 365 \
  -subj "/CN=real-server" 2>/dev/null

# Generate a different key (mismatch)
openssl genrsa -out /opt/cks3-pki/other.key 2048 2>/dev/null

# Present the real cert but the wrong key — this is a mismatch
cp /opt/cks3-pki/real.crt /opt/cks3-pki/check.crt
cp /opt/cks3-pki/other.key /opt/cks3-pki/check.key

chmod 600 /opt/cks3-pki/check.key /opt/cks3-pki/real.key /opt/cks3-pki/other.key

echo "check.crt and check.key are ready — determine if they match"
