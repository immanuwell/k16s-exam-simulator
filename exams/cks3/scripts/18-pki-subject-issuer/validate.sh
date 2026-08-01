#!/usr/bin/env bash
set -eo pipefail

if [[ ! -s /opt/cks3-pki/etcd-subject-issuer.txt ]]; then
  echo "FAIL: /opt/cks3-pki/etcd-subject-issuer.txt is missing or empty"
  exit 1
fi

if ! grep -qi 'subject' /opt/cks3-pki/etcd-subject-issuer.txt; then
  echo "FAIL: etcd-subject-issuer.txt does not contain a Subject line"
  exit 1
fi

if ! grep -qi 'issuer' /opt/cks3-pki/etcd-subject-issuer.txt; then
  echo "FAIL: etcd-subject-issuer.txt does not contain an Issuer line"
  exit 1
fi

ACTUAL_SUBJECT=$(openssl x509 -in /opt/cks3-pki/etcd.crt -noout -subject 2>/dev/null | sed 's/subject=//' | tr -d ' ')
FILE_CONTENT=$(tr -d ' ' < /opt/cks3-pki/etcd-subject-issuer.txt)
if ! echo "$FILE_CONTENT" | grep -qi 'etcd-server'; then
  echo "FAIL: etcd-subject-issuer.txt does not contain the correct Subject CN (etcd-server)"
  exit 1
fi

if ! echo "$FILE_CONTENT" | grep -qi 'etcd-ca'; then
  echo "FAIL: etcd-subject-issuer.txt does not contain the correct Issuer CN (etcd-ca)"
  exit 1
fi

echo "PASS: etcd-subject-issuer.txt contains correct Subject (etcd-server) and Issuer (etcd-ca)"
