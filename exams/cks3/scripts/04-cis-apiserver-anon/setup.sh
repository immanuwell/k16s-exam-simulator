#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

# Ensure the flag is absent so candidate must add it
if grep -q '\-\-anonymous-auth' /etc/kubernetes/manifests/kube-apiserver.yaml; then
  sed -i '/--anonymous-auth/d' /etc/kubernetes/manifests/kube-apiserver.yaml
fi

echo "Environment ready — add --anonymous-auth=false to kube-apiserver manifest"
