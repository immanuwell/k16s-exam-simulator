#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "kubeadm init"

already_done "cluster-init" && { log_skip "kubeadm init"; exit 0; }

NODE_IP="${K16S_NODE_IP:-$(ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+')}"
log_info "Control plane IP: ${NODE_IP}"

K8S_VERSION="${K16S_K8S_VERSION:-1.33}"
POD_CIDR="${K16S_POD_CIDR:-10.244.0.0/16}"
SVC_CIDR="${K16S_SVC_CIDR:-10.96.0.0/12}"

mkdir -p /etc/k16s
cat > /etc/k16s/kubeadm-init.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  name: controlplane
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v${K8S_VERSION}.0"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SVC_CIDR}"
controllerManager:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"
scheduler:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

log_info "Running kubeadm init (this takes ~2 minutes)..."
kubeadm init --config /etc/k16s/kubeadm-init.yaml \
  --upload-certs \
  2>&1 | tee /var/log/kubeadm-init.log

log_ok "kubeadm init complete"

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config
log_ok "kubeconfig written to /root/.kube/config"

kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
log_ok "Control plane untainted"

JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
echo "${JOIN_CMD}" > /etc/k16s/join-command.sh
chmod 600 /etc/k16s/join-command.sh
log_ok "Join command saved to /etc/k16s/join-command.sh"

mark_done "cluster-init"
log_ok "Cluster initialized"
