#!/usr/bin/env bash
set -eo pipefail

CSR="/opt/cks-pki/alice.csr"

if [[ ! -f "$CSR" ]]; then
  echo "FAIL: CSR not found at $CSR"
  exit 1
fi

# Verify it's a valid CSR
if ! openssl req -in "$CSR" -noout 2>/dev/null; then
  echo "FAIL: $CSR is not a valid PEM-encoded CSR"
  exit 1
fi

SUBJECT=$(openssl req -in "$CSR" -noout -subject 2>/dev/null)

# CN=alice
if ! echo "$SUBJECT" | grep -q "CN\s*=\s*alice\|CN = alice"; then
  echo "FAIL: CSR subject missing CN=alice (got: $SUBJECT)"
  exit 1
fi

# O=dev
if ! echo "$SUBJECT" | grep -q "O\s*=\s*dev\b\|O = dev"; then
  echo "FAIL: CSR subject missing O=dev (got: $SUBJECT)"
  exit 1
fi

# O=ops
if ! echo "$SUBJECT" | grep -q "O\s*=\s*ops\b\|O = ops"; then
  echo "FAIL: CSR subject missing O=ops (got: $SUBJECT)"
  exit 1
fi

echo "PASS: alice.csr has correct subject CN=alice O=dev O=ops"
