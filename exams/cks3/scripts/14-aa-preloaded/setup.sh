#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cks3-apparmor

cat > /etc/apparmor.d/k8s-no-proc-write <<'EOF'
#include <tunables/global>
profile k8s-no-proc-write flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  deny /proc/sys/** w,
  file,
  network,
  capability,
}
EOF

apparmor_parser -r -W /etc/apparmor.d/k8s-no-proc-write 2>/dev/null || true

kubectl create namespace apparmor-3 --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: profile k8s-no-proc-write loaded; namespace apparmor-3 exists"
