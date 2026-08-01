#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Write and load the k8s-no-proc-write AppArmor profile
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

# Create the target deployment without AppArmor, pinned to controlplane
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-aa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-aa
  template:
    metadata:
      labels:
        app: web-aa
    spec:
      nodeName: controlplane
      containers:
      - name: web
        image: nginx:alpine
EOF

mkdir -p /opt/cks-apparmor
echo "Profile k8s-no-proc-write loaded; deployment web-aa created in default namespace"
