#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

echo "Environment ready — run kube-bench for master checks and save output to /opt/cks3-cis/"
