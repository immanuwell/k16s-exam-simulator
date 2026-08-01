#!/usr/bin/env bash
set -eo pipefail

if [[ ! -s /opt/cks2-pki/server-crt.txt ]]; then
  echo "FAIL: /opt/cks2-pki/server-crt.txt is missing or empty"
  exit 1
fi

if ! grep -qi "subject" /opt/cks2-pki/server-crt.txt; then
  echo "FAIL: server-crt.txt does not contain Subject information"
  exit 1
fi

if ! grep -q "api.example.com" /opt/cks2-pki/server-crt.txt; then
  echo "FAIL: server-crt.txt does not contain SAN entry api.example.com"
  exit 1
fi

echo "PASS: server-crt.txt contains Subject and SAN entries including api.example.com"
