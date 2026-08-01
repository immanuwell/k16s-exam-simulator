#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create namespace seccomp-override --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /var/lib/kubelet/seccomp/profiles /opt/cks2-seccomp

cat > /var/lib/kubelet/seccomp/profiles/allow-read.json <<'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": ["read", "readv", "openat", "openat2", "close", "fstat", "mmap", "mprotect", "munmap", "brk", "rt_sigaction", "rt_sigprocmask", "ioctl", "access", "execve", "getdents64", "getpid", "socket", "connect", "sendto", "recvfrom", "exit_group", "futex", "set_tid_address", "set_robust_list", "prlimit64", "getrandom"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF

echo "Profile ready at /var/lib/kubelet/seccomp/profiles/allow-read.json — create pod seccomp-override with container-level Localhost override"
