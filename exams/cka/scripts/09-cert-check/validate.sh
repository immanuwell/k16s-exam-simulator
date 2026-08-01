#!/usr/bin/env bash
set -eo pipefail

if [[ ! -s /opt/cka/cert-expiration.txt ]]; then
  echo "FAIL: /opt/cka/cert-expiration.txt is missing or empty"
  exit 1
fi

if ! grep -q 'CERTIFICATE\|certificate\|apiserver\|scheduler' /opt/cka/cert-expiration.txt; then
  echo "FAIL: cert-expiration.txt does not look like kubeadm certs check-expiration output"
  exit 1
fi

if [[ ! -f /opt/cka/soonest-expiring-cert.txt ]]; then
  echo "FAIL: /opt/cka/soonest-expiring-cert.txt not saved"
  exit 1
fi

if [[ ! -f /opt/cka/days-to-expiry.txt ]]; then
  echo "FAIL: /opt/cka/days-to-expiry.txt not saved"
  exit 1
fi

DAYS=$(cat /opt/cka/days-to-expiry.txt | tr -d '[:space:]')
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "FAIL: days-to-expiry.txt must contain an integer (got: '$DAYS')"
  exit 1
fi

CERT=$(cat /opt/cka/soonest-expiring-cert.txt | tr -d '[:space:]')
if [[ -z "$CERT" ]]; then
  echo "FAIL: soonest-expiring-cert.txt is empty"
  exit 1
fi

echo "PASS: cert expiration file saved; soonest-expiring cert=$CERT ($DAYS days)"
