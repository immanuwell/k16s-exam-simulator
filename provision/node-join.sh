#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Install k8s on worker nodes & join cluster"

already_done "node-join" && { log_skip "worker node join"; exit 0; }

export KUBECONFIG=/root/.kube/config
WORKER_COUNT="${CKX_WORKER_COUNT:-2}"
K8S_VERSION="${CKX_K8S_VERSION:-1.33}"
JOIN_CMD_FILE="/etc/ckx/join-command.sh"

[[ -f "${JOIN_CMD_FILE}" ]] || die "Join command not found at ${JOIN_CMD_FILE}. Run cluster-init first."

JOIN_CMD=$(cat "${JOIN_CMD_FILE}")

# source /etc/os-release before the loop — on Debian 13 it exports NAME="Debian GNU/Linux"
# which would clobber any loop variable named NAME
source /etc/os-release
HOST_ID="${ID}"

for i in $(seq 1 "${WORKER_COUNT}"); do
  CNAME="node0${i}"
  log_info "Setting up ${CNAME}..."

  # Some Incus containers may lack working DNS initially
  incus exec "${CNAME}" -- bash -c \
    "grep -q '8.8.8.8' /etc/resolv.conf || echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"

  incus exec "${CNAME}" -- bash -c 'cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true'

  incus exec "${CNAME}" -- bash -c 'cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system -q 2>/dev/null || true'

  if ! incus exec "${CNAME}" -- which containerd &>/dev/null; then
    log_info "  Installing containerd on ${CNAME}..."

    CONTAINER_ID=$(incus exec "${CNAME}" -- bash -c '. /etc/os-release; echo $ID' 2>/dev/null || echo debian)
    CONTAINER_VER=$(incus exec "${CNAME}" -- bash -c '. /etc/os-release; echo $VERSION_CODENAME' 2>/dev/null || echo bookworm)
    # Detect arch from container, not host — avoids `$(...)` inside single-quoted heredoc
    CONTAINER_ARCH=$(incus exec "${CNAME}" -- dpkg --print-architecture 2>/dev/null || echo amd64)

    incus exec "${CNAME}" -- bash -c "
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -q
      apt-get install -y --no-install-recommends curl ca-certificates gpg apt-transport-https

      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/${CONTAINER_ID}/gpg \
        | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg

      echo 'deb [arch=${CONTAINER_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${CONTAINER_ID} ${CONTAINER_VER} stable' \
        > /etc/apt/sources.list.d/docker.list

      apt-get update -q
      apt-get -o Dpkg::Options::='--force-confold' install -y --no-install-recommends containerd.io

      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml
      sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

      systemctl enable containerd
      systemctl restart containerd
    "
    log_ok "  containerd installed on ${CNAME}"
  fi

  if ! incus exec "${CNAME}" -- which kubeadm &>/dev/null; then
    log_info "  Installing kubeadm/kubelet on ${CNAME}..."
    incus exec "${CNAME}" -- bash -c "
      export DEBIAN_FRONTEND=noninteractive
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
        | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /' \
        > /etc/apt/sources.list.d/kubernetes.list

      apt-get update -q
      apt-get install -y --no-install-recommends kubeadm kubelet
      apt-mark hold kubeadm kubelet
      systemctl enable kubelet
    "
    log_ok "  kubeadm/kubelet installed on ${CNAME}"
  fi

  if kubectl get node "${CNAME}" &>/dev/null 2>&1; then
    log_skip "${CNAME} already in cluster"
    continue
  fi

  log_info "  Joining ${CNAME} to cluster..."
  # Clean stale state from any previous failed join attempt
  incus exec "${CNAME}" -- bash -c "
    systemctl stop kubelet 2>/dev/null || true
    kubeadm reset --force 2>/dev/null || true
    rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd 2>/dev/null || true
  "
  # modprobe is not in PATH inside LXC containers — SystemVerification is safe to ignore
  incus exec "${CNAME}" -- bash -c "${JOIN_CMD} --ignore-preflight-errors=SystemVerification" \
    || die "kubeadm join failed on ${CNAME}"
  log_ok "  ${CNAME} joined"
done

log_info "Waiting for all nodes to become Ready..."
for i in $(seq 1 "${WORKER_COUNT}"); do
  kubectl wait node "node0${i}" \
    --for=condition=Ready \
    --timeout=120s \
    || log_warn "node0${i} not Ready yet (may need more time)"
done

log_ok "Cluster nodes:"
kubectl get nodes -o wide

mark_done "node-join"
log_ok "Worker nodes joined"
