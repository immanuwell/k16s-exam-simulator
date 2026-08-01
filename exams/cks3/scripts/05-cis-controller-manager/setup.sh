#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

if grep -q '\-\-profiling' /etc/kubernetes/manifests/kube-controller-manager.yaml; then
  sed -i '/--profiling/d' /etc/kubernetes/manifests/kube-controller-manager.yaml
fi

echo "Environment ready — add --profiling=false to kube-controller-manager manifest"
