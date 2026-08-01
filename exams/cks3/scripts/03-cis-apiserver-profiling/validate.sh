#!/usr/bin/env bash
set -eo pipefail

if ! grep -q '\-\-profiling=false' /etc/kubernetes/manifests/kube-apiserver.yaml; then
  echo "FAIL: --profiling=false not found in kube-apiserver manifest"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/apiserver-profiling.txt ]]; then
  echo "FAIL: /opt/cks3-cis/apiserver-profiling.txt is missing"
  exit 1
fi

if ! grep -q 'profiling' /opt/cks3-cis/apiserver-profiling.txt; then
  echo "FAIL: apiserver-profiling.txt does not contain the profiling flag line"
  exit 1
fi

echo "PASS: --profiling=false is set in kube-apiserver manifest and flag line is saved"
