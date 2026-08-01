#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks3-pki/match-result.txt ]]; then
  echo "FAIL: /opt/cks3-pki/match-result.txt not found"
  exit 1
fi

RESULT=$(cat /opt/cks3-pki/match-result.txt | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [[ "$RESULT" != "match" && "$RESULT" != "mismatch" ]]; then
  echo "FAIL: match-result.txt must contain exactly 'match' or 'mismatch' (got: '$RESULT')"
  exit 1
fi

# Determine the actual answer
CERT_MOD=$(openssl x509 -in /opt/cks3-pki/check.crt -noout -modulus 2>/dev/null)
KEY_MOD=$(openssl rsa -in /opt/cks3-pki/check.key -noout -modulus 2>/dev/null)
if [[ "$CERT_MOD" == "$KEY_MOD" ]]; then
  EXPECTED="match"
else
  EXPECTED="mismatch"
fi

if [[ "$RESULT" != "$EXPECTED" ]]; then
  echo "FAIL: expected '$EXPECTED' but got '$RESULT'"
  exit 1
fi

echo "PASS: match-result.txt correctly says '$RESULT'"
