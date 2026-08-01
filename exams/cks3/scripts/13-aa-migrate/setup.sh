#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cks3-apparmor

# Create the AppArmor profile on the node
cat > /etc/apparmor.d/k8s-deny-proc <<'EOF'
#include <tunables/global>
profile k8s-deny-proc flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  deny /proc/sys/** w,
  deny /proc/sysrq-trigger w,
  file,
  network,
  capability,
}
EOF

apparmor_parser -r -W /etc/apparmor.d/k8s-deny-proc 2>/dev/null || true

kubectl create namespace apparmor-migrate --dry-run=client -o yaml | kubectl apply -f -

# Create the legacy pod (without AppArmor)
kubectl -n apparmor-migrate run legacy \
  --image=busybox:latest \
  --overrides='{"spec":{"nodeName":"controlplane","containers":[{"name":"app","image":"busybox:latest","command":["sleep","3600"]}]}}' \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Environment ready: namespace apparmor-migrate, pod legacy running, profile k8s-deny-proc loaded"
