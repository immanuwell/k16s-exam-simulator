![](media/k16s-logo.png)

![](media/screenshot-1.png)

![](media/screenshot-2.png)

# K16S - Kubernetes Exam Simulator

A self-hosted CKA and CKS exam simulator. It runs a **real kubeadm cluster** — on any Linux VPS, or entirely on your own laptop, no VPS required.

One command to provision. Browser-based terminal. Timed mock exams, with per-question setup and automated grading.

---

## Why K16S

Most Kubernetes practice labs run [kind](https://kind.sigs.k8s.io/) or lightweight k3s clusters. Neither matches the real exam environment:

- `kind` runs every node as a container inside one Docker daemon — no real node isolation, no `systemctl`, no kubelet config files, no `crictl`.
- k3s skips kubeadm-specific workflows entirely — no cluster init, no etcd backup, no static pod manifests, no certificate management.

**K16S runs a real kubeadm cluster**, with [Incus](https://linuxcontainers.org/incus/) LXC containers as worker nodes. Each worker is a full Linux system: its own init, systemd, containerd, kubelet. That's what the actual exam runs.

| Feature | kind / k3d | K16S |
|---|---|---|
| Real kubeadm cluster | ✗ | ✓ |
| `systemctl` on workers | ✗ | ✓ |
| Worker node kubelet config | ✗ | ✓ |
| etcd backup/restore | limited | ✓ |
| Static pod manifests | limited | ✓ |
| `crictl` debugging | ✗ | ✓ |
| Per-question setup + grading | ✗ | ✓ |

---

## What's included

**CKA** — two full mock exams, 18 questions each, covering the [2026 CKA curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/): troubleshooting, cluster architecture, networking, workloads, storage.

**CKS** — three full mock exams, covering the [2026 CKS curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist-cks/): NetworkPolicy, AppArmor, seccomp, CIS benchmarks via kube-bench, API server and kubelet hardening, PKI.

Every question ships with a `setup.sh` that puts the cluster into the exam's broken/incomplete state, and a `validate.sh` that grades your fix against real cluster state.

Full question-by-question breakdown: [DOCS.md § Exam content](DOCS.md#exam-content).

---

## Requirements

Pick one mode:

| Mode | You need |
|---|---|
| **VPS/VM** | Debian 13 or Ubuntu 22.04+, 4 vCPUs / 8 GB RAM / 30 GB disk, root SSH |
| **Laptop** | macOS or Linux, 16 GB+ RAM, [Lima](https://lima-vm.io) |
| **Lightweight** | Docker already running, [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) + `kubectl`, ~2 GB free RAM |

Full details per mode: [DOCS.md § Requirements](DOCS.md#requirements).

---

## Quick start

### Option A — on your laptop (no VPS, no cloud bill)

```bash
git clone https://github.com/immanuwell/k16s-exam-simulator.git
cd k16s-exam-simulator
bash install.sh --laptop
```

Boots a disposable Ubuntu VM with Lima and runs the same provisioner inside it — same kubeadm cluster, same Incus workers, same exam server. Your laptop's own OS is never touched. When it's done, open `http://localhost:8080/`.

Manage it afterward with `local/k16s-local` — `stop` / `start` / `status` / `ssh` / `logs` / `reset` / `destroy`. Full command reference: [DOCS.md § Managing your environment](DOCS.md#managing-your-environment).

### Option B — lightweight, no VM at all (Docker + kind)

```bash
git clone https://github.com/immanuwell/k16s-exam-simulator.git
cd k16s-exam-simulator
bash install.sh --lightweight
```

Runs entirely inside Docker via [kind](https://kind.sigs.k8s.io) — no VM, nothing written to your host OS. Still a real kubeadm cluster underneath, not an approximation: static pods, etcd, and systemd-managed kubelet/containerd are structurally identical to the other two modes.

One trade-off: **AppArmor doesn't work under Docker**, so 8 CKS questions are unavailable — the UI greys them out and excludes them from scoring, so 100% is still reachable. Everything else works the same.

Manage it with `lightweight/k16s-lite`, same command set as laptop mode.

### Option C — on a VPS or VM

```bash
git clone https://github.com/immanuwell/k16s-exam-simulator.git
cd k16s-exam-simulator
bash install.sh --host <your-vm-ip>
```

Installs containerd/kubeadm/kubelet, runs `kubeadm init` with Calico, joins two Incus LXC workers, and deploys the exam server behind nginx.

If `<your-vm-ip>` is a private/LAN address, open `http://<your-vm-ip>/` directly. If it's a public IP, `install.sh` detects that automatically, keeps port 80 off the public internet, opens an SSH tunnel for you, and prints `http://localhost:8080/` instead. Full flag reference (`--tunnel`, `--port`, reconnecting after a dropped tunnel, etc.): [DOCS.md § Installer reference](DOCS.md#installer-reference).

Re-running `install.sh` is always safe — every step is idempotent.

---

## How it works

Pick an exam and a duration in the UI. **Setup Env** puts that question's environment into its broken/incomplete state. Work the problem in the built-in terminal — `kubectl`, `helm`, `etcdctl`, `crictl` all available, workers reachable via `ssh node01` / `ssh node02`. **Check Answer** grades your fix against real cluster and filesystem state, not YAML syntax.

Full architecture, API reference, and runtime file layout: [DOCS.md § Architecture](DOCS.md#architecture).

---

## Adding custom questions

Each question is one YAML file plus two scripts — `setup.sh` and `validate.sh`. Drop them into `exams/<profile>/`, re-run `install.sh`, no rebuild needed.

Full spec: [DOCS.md § Adding custom questions](DOCS.md#adding-custom-questions).

---

## Uninstalling

```bash
bash uninstall.sh --host <your-vm-ip>    # removes the cluster, packages, and candidate user
bash uninstall.sh --laptop               # deletes the Lima VM
bash uninstall.sh --lightweight          # deletes the kind cluster
```

Laptop and lightweight mode are a clean teardown by construction. Details and dry-run mode: [DOCS.md § Uninstalling](DOCS.md#uninstalling).

---

## Troubleshooting

Cluster showing `NotReady` after a reboot, a dropped SSH tunnel, or other common issues: [DOCS.md § Troubleshooting](DOCS.md#troubleshooting).

---

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for personal and non-commercial use; commercial use (including SaaS or paid services built on top of this) requires a separate agreement.
