#!/usr/bin/env bash
set -eo pipefail

if ! grep -q '\-\-anonymous-auth=false' /etc/kubernetes/manifests/kube-apiserver.yaml; then
  echo "FAIL: --anonymous-auth=false not found in kube-apiserver manifest"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/apiserver-anon.txt ]]; then
  echo "FAIL: /opt/cks3-cis/apiserver-anon.txt is missing"
  exit 1
fi

if ! grep -q 'anonymous-auth' /opt/cks3-cis/apiserver-anon.txt; then
  echo "FAIL: apiserver-anon.txt does not contain the anonymous-auth flag line"
  exit 1
fi

echo "PASS: --anonymous-auth=false is set in kube-apiserver manifest and flag line is saved"
