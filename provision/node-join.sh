#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "Install k8s on worker nodes & join cluster"

already_done "node-join" && { log_skip "worker node join"; exit 0; }

export KUBECONFIG=/root/.kube/config
WORKER_COUNT="${CKX_WORKER_COUNT:-1}"
K8S_VERSION="${CKX_K8S_VERSION:-1.33}"
JOIN_CMD_FILE="/etc/ckx/join-command.sh"

[[ -f "${JOIN_CMD_FILE}" ]] || die "Join command not found at ${JOIN_CMD_FILE}. Run cluster-init first."
JOIN_CMD=$(cat "${JOIN_CMD_FILE}")

# source /etc/os-release before the loop — Debian 13 exports NAME="Debian GNU/Linux",
# which would clobber any loop variable named NAME
source /etc/os-release

# ── Phase 1: install containerd + kubeadm on all workers in parallel ──────
#
# Each worker is independent: add Docker + k8s repos in one apt-get update,
# install containerd.io + kubeadm + kubelet in one apt-get install, configure
# containerd. Running workers in parallel halves wall-clock time when >1 worker.

setup_worker() {
  local i=$1
  local CNAME="node0${i}"

  # Ensure DNS
  incus exec "${CNAME}" -- bash -c \
    "grep -q '8.8.8.8' /etc/resolv.conf || echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"

  # Kernel modules + sysctl
  incus exec "${CNAME}" -- bash -c 'cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true
cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system -q 2>/dev/null || true'

  # Skip if tools already present
  if incus exec "${CNAME}" -- which containerd &>/dev/null \
  && incus exec "${CNAME}" -- which kubeadm    &>/dev/null; then
    log_info "  ${CNAME}: containerd + kubeadm already installed"
    return 0
  fi

  # Detect container distro
  local CONTAINER_ID CONTAINER_VER CONTAINER_ARCH
  CONTAINER_ID=$(incus exec "${CNAME}" -- bash -c '. /etc/os-release; echo $ID' 2>/dev/null || echo debian)
  CONTAINER_VER=$(incus exec "${CNAME}" -- bash -c '. /etc/os-release; echo $VERSION_CODENAME' 2>/dev/null || echo bookworm)
  # Detect arch inside container — avoids $(...) evaluation issue inside single-quoted heredocs
  CONTAINER_ARCH=$(incus exec "${CNAME}" -- dpkg --print-architecture 2>/dev/null || echo amd64)

  # Add Docker + k8s repos together, then single apt-get update + install everything
  incus exec "${CNAME}" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive

    apt-get install -y --no-install-recommends curl ca-certificates gpg apt-transport-https

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/${CONTAINER_ID}/gpg \
      | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo 'deb [arch=${CONTAINER_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${CONTAINER_ID} ${CONTAINER_VER} stable' \
      > /etc/apt/sources.list.d/docker.list

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
      | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /' \
      > /etc/apt/sources.list.d/kubernetes.list

    apt-get update -q
    apt-get -o Dpkg::Options::='--force-confold' install -y --no-install-recommends \
      containerd.io kubeadm kubelet
    apt-mark hold kubeadm kubelet

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable containerd
    systemctl restart containerd
    systemctl enable kubelet
  "
  log_ok "  ${CNAME}: containerd + kubeadm installed"
}

join_worker() {
  local i=$1
  local CNAME="node0${i}"

  if kubectl get node "${CNAME}" &>/dev/null 2>&1; then
    log_info "  ${CNAME}: already in cluster"
    return 0
  fi

  # Clean stale state from any previous failed join attempt
  incus exec "${CNAME}" -- bash -c "
    systemctl stop kubelet 2>/dev/null || true
    kubeadm reset --force 2>/dev/null || true
    rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd 2>/dev/null || true
  "

  # modprobe is not in PATH inside LXC containers — SystemVerification is safe to ignore
  incus exec "${CNAME}" -- bash -c "${JOIN_CMD} --ignore-preflight-errors=SystemVerification"
  log_ok "  ${CNAME}: joined cluster"
}

# ── Run setup in parallel across all workers ──────────────────────────────

log_info "Setting up ${WORKER_COUNT} worker node(s) in parallel..."
SETUP_PIDS=()
for i in $(seq 1 "${WORKER_COUNT}"); do
  setup_worker "${i}" > "/var/log/ckx-node0${i}-setup.log" 2>&1 &
  SETUP_PIDS+=($!)
done

FAILED=0
for i in $(seq 1 "${WORKER_COUNT}"); do
  if wait "${SETUP_PIDS[$((i-1))]}"; then
    log_ok "node0${i} setup done"
  else
    log_warn "node0${i} setup FAILED — see /var/log/ckx-node0${i}-setup.log"
    FAILED=$((FAILED + 1))
  fi
done
[[ "${FAILED}" -eq 0 ]] || die "${FAILED} worker node(s) failed during setup"

# ── Run kubeadm join in parallel ─────────────────────────────────────────

log_info "Joining ${WORKER_COUNT} worker node(s) to cluster..."
JOIN_PIDS=()
for i in $(seq 1 "${WORKER_COUNT}"); do
  join_worker "${i}" > "/var/log/ckx-node0${i}-join.log" 2>&1 &
  JOIN_PIDS+=($!)
done

FAILED=0
for i in $(seq 1 "${WORKER_COUNT}"); do
  if wait "${JOIN_PIDS[$((i-1))]}"; then
    log_ok "node0${i} joined"
  else
    log_warn "node0${i} join FAILED — see /var/log/ckx-node0${i}-join.log"
    FAILED=$((FAILED + 1))
  fi
done
[[ "${FAILED}" -eq 0 ]] || die "${FAILED} worker node(s) failed to join cluster"

# ── Wait for nodes Ready ──────────────────────────────────────────────────

log_info "Waiting for all nodes to become Ready..."
for i in $(seq 1 "${WORKER_COUNT}"); do
  kubectl wait node "node0${i}" \
    --for=condition=Ready \
    --timeout=120s \
    || log_warn "node0${i} not Ready yet (kubelet may need more time)"
done

log_ok "Cluster nodes:"
kubectl get nodes -o wide

mark_done "node-join"
log_ok "Worker nodes joined"
