#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

# Remove the flags so the candidate must add them
sed -i '/client-cert-auth/d' /etc/kubernetes/manifests/etcd.yaml
sed -i '/peer-client-cert-auth/d' /etc/kubernetes/manifests/etcd.yaml

echo "Environment ready — add --client-cert-auth=true and --peer-client-cert-auth=true to etcd manifest"
