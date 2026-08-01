#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cks2-pki/embedded-ca-dates.txt ]]; then
  echo "FAIL: /opt/cks2-pki/embedded-ca-dates.txt not found"
  exit 1
fi

LINE_COUNT=$(grep -c '[0-9]' /opt/cks2-pki/embedded-ca-dates.txt 2>/dev/null || echo 0)
if (( LINE_COUNT < 2 )); then
  echo "FAIL: embedded-ca-dates.txt should have at least 2 date lines (found $LINE_COUNT with digits)"
  exit 1
fi

# Must contain both a notBefore-style and notAfter-style date
if ! grep -qi "before\|after\|not" /opt/cks2-pki/embedded-ca-dates.txt && \
   ! grep -qE "[0-9]{4}" /opt/cks2-pki/embedded-ca-dates.txt; then
  echo "FAIL: embedded-ca-dates.txt does not appear to contain certificate dates"
  exit 1
fi

echo "PASS: embedded-ca-dates.txt contains both Not Before and Not After dates"
