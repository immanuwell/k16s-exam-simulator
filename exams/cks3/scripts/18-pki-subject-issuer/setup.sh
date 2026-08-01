#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-pki

openssl genrsa -out /opt/cks3-pki/ca-etcd.key 2048 2>/dev/null
openssl req -new -x509 -key /opt/cks3-pki/ca-etcd.key \
  -out /opt/cks3-pki/ca-etcd.crt -days 3650 \
  -subj "/CN=etcd-ca/O=system:masters" 2>/dev/null

openssl genrsa -out /opt/cks3-pki/etcd.key 2048 2>/dev/null
openssl req -new -key /opt/cks3-pki/etcd.key \
  -out /opt/cks3-pki/etcd.csr \
  -subj "/CN=etcd-server/O=system:masters" 2>/dev/null
openssl x509 -req -in /opt/cks3-pki/etcd.csr \
  -CA /opt/cks3-pki/ca-etcd.crt -CAkey /opt/cks3-pki/ca-etcd.key \
  -CAcreateserial -out /opt/cks3-pki/etcd.crt -days 365 2>/dev/null

echo "Certificate ready at /opt/cks3-pki/etcd.crt — extract Subject and Issuer"
