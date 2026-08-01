#!/usr/bin/env bash
set -eo pipefail

mkdir -p /var/lib/kubelet/seccomp/profiles
mkdir -p /opt/cks-seccomp
echo "Directory /var/lib/kubelet/seccomp/profiles/ is ready — create your audit-write profile there"
