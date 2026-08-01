#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

# Remove --profiling flag if already set so candidate must add it
if grep -q '\-\-profiling' /etc/kubernetes/manifests/kube-apiserver.yaml; then
  sed -i '/--profiling/d' /etc/kubernetes/manifests/kube-apiserver.yaml
fi

echo "Environment ready — add --profiling=false to kube-apiserver manifest"
