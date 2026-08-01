#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cka

echo "Environment ready — take an etcd snapshot to /opt/cka/etcd-backup.db"
