#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks2-pki/self.crt ]]; then
  echo "FAIL: /opt/cks2-pki/self.crt not found"
  exit 1
fi

if ! openssl x509 -in /opt/cks2-pki/self.crt -noout 2>/dev/null; then
  echo "FAIL: /opt/cks2-pki/self.crt is not a valid PEM certificate"
  exit 1
fi

SUBJECT=$(openssl x509 -in /opt/cks2-pki/self.crt -noout -subject 2>/dev/null)
if ! echo "$SUBJECT" | grep -q "self-signed"; then
  echo "FAIL: certificate subject does not contain CN=self-signed (got: $SUBJECT)"
  exit 1
fi

END_DATE=$(openssl x509 -in /opt/cks2-pki/self.crt -noout -enddate 2>/dev/null | cut -d= -f2)
END_EPOCH=$(date -d "$END_DATE" +%s 2>/dev/null || python3 -c "
from datetime import datetime
print(int(datetime.strptime('$END_DATE','%b %d %H:%M:%S %Y %Z').timestamp()))
")
NOW_EPOCH=$(date +%s)
DAYS=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))
if (( DAYS < 300 )); then
  echo "FAIL: certificate expires in $DAYS days, expected ~365"
  exit 1
fi

echo "PASS: self.crt is a valid self-signed certificate with CN=self-signed, valid for ~$DAYS days"
