#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks3-pki/user.key ]]; then
  echo "FAIL: /opt/cks3-pki/user.key not found"
  exit 1
fi

PERMS=$(stat -c '%a' /opt/cks3-pki/user.key)
if [[ "$PERMS" != "600" ]]; then
  echo "FAIL: /opt/cks3-pki/user.key permissions are $PERMS (expected 600)"
  exit 1
fi

KEY_INFO=$(openssl rsa -in /opt/cks3-pki/user.key -text -noout 2>/dev/null | grep 'Private-Key')
if ! echo "$KEY_INFO" | grep -q '3072'; then
  echo "FAIL: key is not 3072 bits (got: $KEY_INFO)"
  exit 1
fi

echo "PASS: /opt/cks3-pki/user.key is a 3072-bit RSA key with permissions 600"
