#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cka

echo "Environment ready — run kubeadm certs check-expiration and analyze the output"
