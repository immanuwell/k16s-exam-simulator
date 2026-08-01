#!/usr/bin/env bash
set -eo pipefail

KEY="/opt/cks-pki/user.key"

if [[ ! -f "$KEY" ]]; then
  echo "FAIL: key file not found at $KEY"
  exit 1
fi

# Check permissions are 0600
PERMS=$(stat -c '%a' "$KEY")
if [[ "$PERMS" != "600" ]]; then
  echo "FAIL: $KEY permissions are $PERMS, expected 600"
  exit 1
fi

# Check key is valid RSA and 3072-bit
KEY_INFO=$(openssl pkey -in "$KEY" -text -noout 2>/dev/null)
if ! echo "$KEY_INFO" | grep -q "3072 bit\|Private-Key: (3072 bit)"; then
  echo "FAIL: $KEY is not a 3072-bit RSA key (got: $(echo "$KEY_INFO" | head -2))"
  exit 1
fi

echo "PASS: /opt/cks-pki/user.key is a 3072-bit RSA key with permissions 0600"
