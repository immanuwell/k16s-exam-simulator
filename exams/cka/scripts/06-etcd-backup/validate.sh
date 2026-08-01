#!/usr/bin/env bash
set -eo pipefail

if [[ ! -f /opt/cka/etcd-backup.db ]]; then
  echo "FAIL: /opt/cka/etcd-backup.db not found"
  exit 1
fi

if [[ ! -s /opt/cka/etcd-backup.db ]]; then
  echo "FAIL: /opt/cka/etcd-backup.db is empty"
  exit 1
fi

# Verify snapshot integrity
VERIFY=$(ETCDCTL_API=3 etcdctl snapshot status /opt/cka/etcd-backup.db \
  --write-out=table 2>&1) || {
  echo "FAIL: etcd snapshot is corrupt or invalid"
  echo "$VERIFY"
  exit 1
}

if [[ ! -f /opt/cka/etcd-backup-status.txt ]]; then
  echo "FAIL: /opt/cka/etcd-backup-status.txt not saved"
  exit 1
fi

if ! grep -q 'hash\|revision\|total' /opt/cka/etcd-backup-status.txt 2>/dev/null; then
  echo "FAIL: etcd-backup-status.txt does not look like etcdctl snapshot status output"
  exit 1
fi

echo "PASS: etcd snapshot saved and verified — $(du -sh /opt/cka/etcd-backup.db | cut -f1)"
