#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace apparmor-multi --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /opt/cks2-apparmor

cat > /etc/apparmor.d/k8s-readonly <<'EOF'
#include <tunables/global>

profile k8s-readonly flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  file,
  network,
  capability,
  mount,
  umount,
  signal,
  ptrace,
  pivot_root,
  deny /** w,
}
EOF
apparmor_parser -r -W /etc/apparmor.d/k8s-readonly

cat > /etc/apparmor.d/k8s-tmpwrite <<'EOF'
#include <tunables/global>

profile k8s-tmpwrite flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  file,
  network,
  capability,
  mount,
  umount,
  signal,
  ptrace,
  pivot_root,
  /tmp/** rw,
  deny /** w,
}
EOF
apparmor_parser -r -W /etc/apparmor.d/k8s-tmpwrite

echo "Profiles k8s-readonly and k8s-tmpwrite are loaded — create multi-container pod multi-aa in apparmor-multi"
