#!/usr/bin/env bash
set -eo pipefail

if ! grep -q '\-\-client-cert-auth=true' /etc/kubernetes/manifests/etcd.yaml; then
  echo "FAIL: --client-cert-auth=true not found in etcd manifest"
  exit 1
fi

if ! grep -q '\-\-peer-client-cert-auth=true' /etc/kubernetes/manifests/etcd.yaml; then
  echo "FAIL: --peer-client-cert-auth=true not found in etcd manifest"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/etcd-cert-auth.txt ]]; then
  echo "FAIL: /opt/cks3-cis/etcd-cert-auth.txt is missing"
  exit 1
fi

if ! grep -q 'client-cert-auth' /opt/cks3-cis/etcd-cert-auth.txt; then
  echo "FAIL: etcd-cert-auth.txt does not contain the client-cert-auth flag"
  exit 1
fi

if ! grep -q 'peer-client-cert-auth' /opt/cks3-cis/etcd-cert-auth.txt; then
  echo "FAIL: etcd-cert-auth.txt does not contain the peer-client-cert-auth flag"
  exit 1
fi

echo "PASS: etcd has --client-cert-auth=true and --peer-client-cert-auth=true; both flag lines saved"
