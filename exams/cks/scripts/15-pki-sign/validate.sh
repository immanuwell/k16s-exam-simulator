#!/usr/bin/env bash
set -eo pipefail

CA_CERT="/opt/cks-pki/ca.crt"
APP_CERT="/opt/cks-pki/app.crt"

if [[ ! -f "$APP_CERT" ]]; then
  echo "FAIL: signed certificate not found at $APP_CERT"
  exit 1
fi

# Verify certificate is valid PEM
if ! openssl x509 -in "$APP_CERT" -noout 2>/dev/null; then
  echo "FAIL: $APP_CERT is not a valid PEM certificate"
  exit 1
fi

# Verify chain
VERIFY=$(openssl verify -CAfile "$CA_CERT" "$APP_CERT" 2>&1)
if ! echo "$VERIFY" | grep -q ": OK"; then
  echo "FAIL: certificate does not verify against CA: $VERIFY"
  exit 1
fi

# Check CN=app.svc
SUBJECT=$(openssl x509 -in "$APP_CERT" -noout -subject 2>/dev/null)
if ! echo "$SUBJECT" | grep -q "CN\s*=\s*app\.svc\|CN = app.svc"; then
  echo "FAIL: certificate subject missing CN=app.svc (got: $SUBJECT)"
  exit 1
fi

# Check validity is at least 300 days (allowing for slight clock drift vs 365)
END_DATE=$(openssl x509 -in "$APP_CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
END_EPOCH=$(date -d "$END_DATE" +%s 2>/dev/null || python3 -c "from datetime import datetime; print(int(datetime.strptime('$END_DATE','%b %d %H:%M:%S %Y %Z').timestamp()))")
NOW_EPOCH=$(date +%s)
DAYS=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))
if (( DAYS < 300 )); then
  echo "FAIL: certificate expires in $DAYS days, expected ~365"
  exit 1
fi

echo "PASS: app.crt is signed by the CA, has CN=app.svc, valid for ~$DAYS days"
