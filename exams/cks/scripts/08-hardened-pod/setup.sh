#!/usr/bin/env bash
set -eo pipefail

# Load k8s-no-proc-write if not already loaded
if ! aa-status --json 2>/dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); exit(0 if 'k8s-no-proc-write' in d['profiles'] else 1)" \
    2>/dev/null; then
  cat > /etc/apparmor.d/k8s-no-proc-write <<'EOF'
#include <tunables/global>

profile k8s-no-proc-write flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  file,
  network,
  capability,
  mount,
  umount,
  signal,
  ptrace,
  pivot_root,

  deny /proc/sys/** w,
}
EOF
  apparmor_parser -r -W /etc/apparmor.d/k8s-no-proc-write
fi

mkdir -p /opt/cks-security
echo "AppArmor profile k8s-no-proc-write is loaded; create pod 'hardened' with it + RuntimeDefault seccomp"
