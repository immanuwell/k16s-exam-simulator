#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks2-pki/ca2.crt ]]; then
  echo "FAIL: /opt/cks2-pki/ca2.crt not found"
  exit 1
fi

if ! openssl x509 -in /opt/cks2-pki/ca2.crt -noout 2>/dev/null; then
  echo "FAIL: /opt/cks2-pki/ca2.crt is not a valid PEM certificate"
  exit 1
fi

SUBJECT=$(openssl x509 -in /opt/cks2-pki/ca2.crt -noout -subject 2>/dev/null)
if ! echo "$SUBJECT" | grep -q "cluster-ca"; then
  echo "FAIL: certificate subject does not contain CN=cluster-ca (got: $SUBJECT)"
  exit 1
fi

END_DATE=$(openssl x509 -in /opt/cks2-pki/ca2.crt -noout -enddate 2>/dev/null | cut -d= -f2)
END_EPOCH=$(date -d "$END_DATE" +%s 2>/dev/null || python3 -c "
from datetime import datetime
print(int(datetime.strptime('$END_DATE','%b %d %H:%M:%S %Y %Z').timestamp()))
")
NOW_EPOCH=$(date +%s)
DAYS=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))
if (( DAYS < 700 )); then
  echo "FAIL: certificate expires in $DAYS days, expected ~730"
  exit 1
fi

CERT_TEXT=$(openssl x509 -in /opt/cks2-pki/ca2.crt -noout -text 2>/dev/null)
if ! echo "$CERT_TEXT" | grep -q "CA:TRUE"; then
  echo "FAIL: ca2.crt is not a CA certificate (Basic Constraints: CA:TRUE not found)"
  exit 1
fi

echo "PASS: ca2.crt is a valid CA certificate with CN=cluster-ca, valid for ~$DAYS days"
