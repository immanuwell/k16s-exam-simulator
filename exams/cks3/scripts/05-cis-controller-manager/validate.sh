#!/usr/bin/env bash
set -eo pipefail

if ! grep -q '\-\-profiling=false' /etc/kubernetes/manifests/kube-controller-manager.yaml; then
  echo "FAIL: --profiling=false not found in kube-controller-manager manifest"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/controller-manager-profiling.txt ]]; then
  echo "FAIL: /opt/cks3-cis/controller-manager-profiling.txt is missing"
  exit 1
fi

if ! grep -q 'profiling' /opt/cks3-cis/controller-manager-profiling.txt; then
  echo "FAIL: controller-manager-profiling.txt does not contain profiling flag"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/controller-manager-sa-creds.txt ]]; then
  echo "FAIL: /opt/cks3-cis/controller-manager-sa-creds.txt is missing"
  exit 1
fi

if ! grep -q 'service-account-credentials' /opt/cks3-cis/controller-manager-sa-creds.txt; then
  echo "FAIL: controller-manager-sa-creds.txt does not contain the flag line"
  exit 1
fi

echo "PASS: --profiling=false set on controller-manager; both flag files saved"
