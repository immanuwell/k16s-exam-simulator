#!/usr/bin/env bash
set -eo pipefail

# Create the AppArmor profile file for the student to load — do NOT load it.
cat > /etc/apparmor.d/k8s-deny-etc <<'EOF'
#include <tunables/global>

profile k8s-deny-etc flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  file,
  network,
  capability,
  mount,
  umount,
  signal,
  ptrace,
  pivot_root,

  deny /etc/** w,
}
EOF

mkdir -p /opt/cks-apparmor
echo "Profile file written to /etc/apparmor.d/k8s-deny-etc — load it with: apparmor_parser -r -W /etc/apparmor.d/k8s-deny-etc"
