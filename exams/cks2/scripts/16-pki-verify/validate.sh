#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks2-pki/verify-result.txt ]]; then
  echo "FAIL: /opt/cks2-pki/verify-result.txt not found"
  exit 1
fi

if ! grep -q "OK" /opt/cks2-pki/verify-result.txt; then
  echo "FAIL: verify-result.txt does not contain 'OK' (content: $(cat /opt/cks2-pki/verify-result.txt))"
  exit 1
fi

echo "PASS: verify-result.txt confirms certificate verification OK"
