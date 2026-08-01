#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks3-pki/alice.csr ]]; then
  echo "FAIL: /opt/cks3-pki/alice.csr not found"
  exit 1
fi

SUBJECT=$(openssl req -in /opt/cks3-pki/alice.csr -noout -subject 2>/dev/null)
if ! echo "$SUBJECT" | grep -q 'CN\s*=\s*alice\|CN = alice'; then
  echo "FAIL: CSR subject does not contain CN=alice (got: $SUBJECT)"
  exit 1
fi

if ! echo "$SUBJECT" | grep -q 'O\s*=\s*dev\|O = dev'; then
  echo "FAIL: CSR subject does not contain O=dev (got: $SUBJECT)"
  exit 1
fi

if ! echo "$SUBJECT" | grep -q 'O\s*=\s*ops\|O = ops'; then
  echo "FAIL: CSR subject does not contain O=ops (got: $SUBJECT)"
  exit 1
fi

if ! openssl req -in /opt/cks3-pki/alice.csr -noout -verify 2>/dev/null; then
  echo "FAIL: CSR signature verification failed"
  exit 1
fi

echo "PASS: alice.csr has CN=alice with organizations dev and ops"
