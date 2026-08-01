#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Save backup of current manifest
cp /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler-backup.yaml

# Inject an invalid flag — causes the scheduler to fail to start
if ! grep -q '\-\-invalid-scheduling-mode' /etc/kubernetes/manifests/kube-scheduler.yaml; then
  sed -i '/--leader-elect=true/a\    - --invalid-scheduling-mode=broken' \
    /etc/kubernetes/manifests/kube-scheduler.yaml
fi

echo "Bad flag injected into kube-scheduler manifest — scheduler will fail to start"
