# K16S Documentation

Full reference for installing, running, and extending K16S. For the quick pitch and quick start, see [README.md](README.md).

## Contents

- [Requirements](#requirements)
- [Installer reference](#installer-reference)
- [Managing your environment](#managing-your-environment)
- [Exam content](#exam-content)
- [How an exam works](#how-an-exam-works)
- [Architecture](#architecture)
- [Adding custom questions](#adding-custom-questions)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)

## Requirements

### VPS / VM mode (`--host`)

| | |
|---|---|
| OS | Debian 13 (trixie) or Ubuntu 22.04+ |
| Resources | 4 vCPUs, 8 GB RAM, 30 GB disk (minimum) |
| Access | Root SSH access |
| Network | Port 80 reachable from wherever you run `install.sh`, nothing needs to be open to the public internet, see [Public vs. private targets](#public-vs-private-targets) |

### Laptop mode (`--laptop`)

| | |
|---|---|
| OS | macOS or Linux |
| Resources | 16 GB+ RAM recommended (the VM itself uses 8 GB) |
| Tooling | [Lima](https://lima-vm.io) - `brew install lima` (macOS) or `apt install lima` / release binary (Linux) |
| Windows | Not supported natively. WSL2 users can follow the Linux path, unverified |

Guest OS is Ubuntu 24.04 (not Debian 13) - chosen for Lima's more battle-tested cloud image support. This has no effect on exam content: the guest runs the exact same provisioner as VPS mode.

### Lightweight mode (`--lightweight`)

| | |
|---|---|
| Requirement | Docker (or a Docker-compatible engine), already running |
| Tooling | [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) and `kubectl` |
| Resources | ~2 GB RAM free (measured ~1.6 GB RSS for a 2-node cluster with Calico, before the exam server) |
| Host impact | None, everything lives inside Docker's own storage |

One capability gap: AppArmor doesn't work under Docker (it doesn't expose kernel securityfs to containers). 8 questions across the CKS mocks need it - see [Exam content](#exam-content).

## Installer reference

### `install.sh`

```bash
bash install.sh [--profile cka] [--k8s 1.33] [--workers 1]                    # on the VM directly
bash install.sh --host <ip> [--key PATH] [--user root] [--tunnel|--no-tunnel] [--port 8080]
bash install.sh --laptop [--profile cka] [--cpus 4] [--memory 8] [--disk 30] [--desktop] [--port 8080]
bash install.sh --lightweight [--profile cka] [--workers 1] [--k8s-image kindest/node:vX.Y.Z] [--port 8080]
```

| Flag | Meaning |
|---|---|
| `--host <ip>` | Provision a remote VM over SSH instead of the local machine |
| `--key <path>` | SSH private key for `--host` (default: your SSH agent / default key) |
| `--user <name>` | SSH user for `--host` (default: `root`) |
| `--laptop` | Provision inside a local Lima VM, see [Laptop mode](#laptop-mode-lima) |
| `--lightweight` | Provision inside a kind cluster, see [Lightweight mode](#lightweight-mode-kind) |
| `--profile <name>` | Env-setup profile to apply on the controlplane (only `cka` exists today, it exports etcdctl cert env vars for the candidate). Doesn't control which exams are available; the exam UI always loads every exam bundled in `exams/` |
| `--k8s <version>` | Kubernetes minor version (`--host`/bare VM only) |
| `--workers <n>` | Number of worker nodes (`--host`, `--lightweight`; laptop mode via its own flag below) |
| `--no-desktop` | Skip the noVNC desktop step (`--host`/bare VM only) |
| `--desktop` | Add the noVNC desktop (laptop mode only, off by default there) |
| `--cpus / --memory / --disk` | VM sizing, laptop mode only |
| `--tunnel` / `--no-tunnel` | Force or disable the SSH tunnel for `--host`, overriding auto-detection |
| `--port <n>` | Local port for the tunnel (`--host`) or forwarded port (laptop/lightweight). Default `8080` |
| `--k8s-image <image>` | kind node image, lightweight mode only |

Re-running `install.sh` is always safe - every provisioning step is idempotent and skips work already done.

#### Public vs. private targets

For `--host`, `install.sh` classifies the target IP automatically:

- **Private** (`10.x`, `172.16-31.x`, `192.168.x`, loopback, link-local, CGNAT) - nginx binds all interfaces. `install.sh` prints `http://<ip>/` directly.
- **Public** (a real internet-facing VPS), or unresolvable, nginx binds `127.0.0.1` only, and `install.sh` opens an SSH tunnel automatically. It prints `http://localhost:8080/` instead. Port 80 is never reachable from the public internet - only from wherever you ran `install.sh`, over the SSH access you already needed.

An unresolvable hostname is treated as public - classification failure always fails toward privacy, never toward silently exposing port 80.

### `uninstall.sh`

```bash
bash uninstall.sh [--yes] [--dry-run]                     # on the VM directly
bash uninstall.sh --host <ip> [--key PATH] [--yes] [--dry-run]
bash uninstall.sh --laptop [--yes]
bash uninstall.sh --lightweight [--yes]
```

| Flag | Meaning |
|---|---|
| `--yes` / `-y` | Skip the confirmation prompt |
| `--dry-run` | Print what would be removed without touching anything (VPS/host mode only) |

See [Uninstalling](#uninstalling) for what actually gets removed.

### `k16s-tunnel`

Manages the SSH tunnel `install.sh` opens automatically for public `--host` targets. Useful for reconnecting after your laptop sleeps or the connection drops, without re-running the installer.

```bash
./k16s-tunnel up <host>     [--port 8080] [--key ~/.ssh/id] [--user root]
./k16s-tunnel down <host>
./k16s-tunnel status <host>
```

State lives at `~/.k16s/tunnels/<host>.{pid,port,log}`. `up` is idempotent, running it against an already-open tunnel is a no-op.

## Managing your environment

Once provisioned, `local/k16s-local` (laptop mode) and `lightweight/k16s-lite` (lightweight mode) manage the whole lifecycle. Both share the same command shape:

```bash
local/k16s-local <command>        # or: lightweight/k16s-lite <command>
```

| Command | Effect |
|---|---|
| `up` | Create the VM/cluster and provision it. Flags: `--profile`, `--k8s`, `--workers`, `--desktop`/`--no-desktop`, `--cpus`, `--memory`, `--disk`, `--port` (laptop only, as applicable) |
| `stop` | Suspend the VM/cluster - frees RAM/CPU, state preserved |
| `start` | Resume from `stop` |
| `restart` | `stop` then `start` |
| `status` | Current state, plus the exam UI and terminal URLs |
| `ssh` | Shell into the controlplane. Add `--root` for `sudo -i` |
| `logs [target]` | Tail logs. `target` is one of `server` (default), `kubelet`, `terminal`, or `desktop` (laptop only) |
| `open` | Open the exam UI in your default browser |
| `reset` | Wipe and re-provision from scratch. Add `--yes` to skip confirmation |
| `destroy` | Delete the VM/cluster entirely. Add `--yes` to skip confirmation |

Laptop mode only:

| Command | Effect |
|---|---|
| `snapshot` | Save a `clean` snapshot (qemu driver only, not supported on Lima's vz driver) |
| `revert` | Restore the `clean` snapshot. Add `--yes` to skip confirmation |

`reset` destroys and recreates the whole VM/cluster rather than trying to reset kubeadm/Incus state in place - safer, since stale `/etc/kubernetes` or `/var/lib/kubelet` state is a known way to break a rejoin. `destroy` is a complete teardown by construction: deleting the Lima VM's disk, or running `kind delete cluster`, removes everything K16S ever touched.

See [`local/lima.yaml`](local/lima.yaml) for the VM template.

## Exam content

Every exam bundled in `exams/` is loaded by the server at startup, pick which one to attempt from the exam UI, no install-time flag needed.

### CKA - Certified Kubernetes Administrator

Covers the [2026 CKA curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/). Two mocks, 18 questions each.

**CKA Mock 1** - core administration:

| # | Question |
|---|---|
| 1 | Fix a NotReady Worker Node |
| 2 | Fix a CrashLoopBackOff Pod |
| 3 | Fix a Pending Pod, Node Selector |
| 4 | Fix the Broken kube-scheduler |
| 5 | Identify Highest Resource-Consuming Pods |
| 6 | Back Up and Verify etcd |
| 7 | Drain a Node for Maintenance |
| 8 | RBAC, ServiceAccount, Role, and RoleBinding |
| 9 | Check Cluster Certificate Expiration |
| 10 | Create a Static Pod on a Worker Node |
| 11 | NetworkPolicy, Restrict Pod-to-Pod Traffic |
| 12 | Gateway API, Create a Gateway and HTTPRoute |
| 13 | Create a Path-Based Ingress |
| 14 | Add a CoreDNS Stub Zone for an Internal Domain |
| 15 | Configure HorizontalPodAutoscaler for a Deployment |
| 16 | Create a DaemonSet on Labeled Nodes |
| 17 | Pod with Sidecar Container and Shared Volume |
| 18 | PersistentVolume, PVC, and Pod with Volume Mount |

**CKA Mock 2** - advanced and 2026-updated topics:

| # | Question |
|---|---|
| 1 | Fix the Broken kube-apiserver |
| 2 | Fix an OOMKilled Pod |
| 3 | Fix a Broken Service Selector |
| 4 | Fix Deployment Blocked by ResourceQuota |
| 5 | Investigate Cluster Events and Pod Failures |
| 6 | ClusterRole and ClusterRoleBinding for Node Inspection |
| 7 | Create a kubeconfig for a ServiceAccount |
| 8 | Manually Schedule a Pod Without the Scheduler |
| 9 | Apply a Kustomize Overlay |
| 10 | Create a PriorityClass and Assign it to a Deployment |
| 11 | Create a Job and a CronJob |
| 12 | Create a Secret and Mount it Two Ways |
| 13 | Headless Service and DNS Resolution |
| 14 | Egress NetworkPolicy with DNS Exception |
| 15 | Named Container Port and NodePort Service |
| 16 | Create a Default StorageClass |
| 17 | Recover a Released PersistentVolume |
| 18 | Install a Helm Chart and Template Without CRDs |

### CKS - Certified Kubernetes Security Specialist

Covers the [2026 CKS curriculum](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist-cks/). Three mocks, 18 (CKS 1: 15) questions each.

Questions marked 🔒 need AppArmor and are unavailable in [lightweight mode](#lightweight-mode-kind), excluded from scoring there, so 100% stays reachable.

**CKS Mock 1:**

| # | Question | |
|---|---|---|
| 1 | Restrict Pod Ingress with a NetworkPolicy | |
| 2 | Implement Egress Controls with NetworkPolicy | |
| 3 | Block Cloud Metadata Endpoint via NetworkPolicy | |
| 4 | Allow Only Intra-Namespace Traffic | |
| 5 | Restrict SSH Access by CIDR with Exception | |
| 6 | Load an AppArmor Profile and Apply It to a Pod | 🔒 |
| 7 | Apply an AppArmor Profile to a Deployment | 🔒 |
| 8 | Create a Pod Hardened with AppArmor and Seccomp | 🔒 |
| 9 | Create a Custom Seccomp Profile to Block mkdir | |
| 10 | Enable RuntimeDefault Seccomp on a Deployment | |
| 11 | Replace an Unconfined Pod with RuntimeDefault Seccomp | |
| 12 | Create an Audit Seccomp Profile for Write Syscalls | |
| 13 | Generate an RSA Private Key | |
| 14 | Create a Certificate Signing Request for a User | |
| 15 | Sign a Certificate Signing Request with a CA | |

**CKS Mock 2:**

| # | Question | |
|---|---|---|
| 1 | Cross-Namespace Ingress for API Pods | |
| 2 | Restrict Backend Egress to Database and DNS | |
| 3 | Microsegmentation, Deny All Ingress, Selective Worker Egress | |
| 4 | Lock Down Proxy Pods with Ingress and Egress Allowlists | |
| 5 | Ingress with matchExpressions Pod Selector | |
| 6 | Lock Down Log Collector Ingress and Egress | |
| 7 | Create a Custom AppArmor Profile for /tmp Writes | 🔒 |
| 8 | Override Pod-Level Seccomp with a Container Localhost Profile | |
| 9 | Audit and Remediate Pods Without Seccomp | |
| 10 | Block Mount Syscalls via Seccomp on a Deployment | |
| 11 | Create an AppArmor Profile Restricting /proc/sys Writes | 🔒 |
| 12 | Apply Different AppArmor Profiles to Two Containers | 🔒 |
| 13 | Inspect a Server Certificate | |
| 14 | Create a CSR with Subject Alternative Names | |
| 15 | Create a Self-Signed Certificate | |
| 16 | Verify a Certificate Against a CA | |
| 17 | Create a Self-Signed CA Certificate | |
| 18 | Extract Validity Dates from a Base64-Encoded Certificate | |

**CKS Mock 3** - CIS benchmark and kube-bench focus:

| # | Question | |
|---|---|---|
| 1 | Run kube-bench for Control Plane Checks | |
| 2 | Run kube-bench for Node Checks | |
| 3 | Disable kube-apiserver Profiling (CIS 1.2.21) | |
| 4 | Disable Anonymous Auth on kube-apiserver (CIS 1.2.1) | |
| 5 | Disable Profiling on kube-controller-manager (CIS 1.3.2) | |
| 6 | Harden Kubelet Authentication and Authorization (CIS 4.2.1/4.2.2) | |
| 7 | Enable etcd Client and Peer Certificate Auth (CIS 2.1/2.2) | |
| 8 | Disable Kubelet Read-Only Port (CIS 4.2.4) | |
| 9 | Restrict Ingress to Prod Namespace Pods Only | |
| 10 | Staging Ingress Allowlist with Multi-Port and CIDR | |
| 11 | Zone-Based Ingress and Egress with DMZ and Internal Namespaces | |
| 12 | Allow HTTPS Egress While Blocking Cloud Metadata and Private Ranges | |
| 13 | Replace a Legacy Pod with AppArmor Enforcement | 🔒 |
| 14 | Apply a Preloaded AppArmor Profile via Pod Annotation | 🔒 |
| 15 | Generate a 3072-bit RSA Private Key | |
| 16 | Create a CSR with Multiple Organizations | |
| 17 | Determine Whether a Certificate and Key Match | |
| 18 | Extract Subject and Issuer from a Certificate | |

## How an exam works

1. **Pick an exam and duration** in the UI (CKA 1, CKA 2, CKS 1, CKS 2, CKS 3, any duration).
2. **Setup Env** - runs that question's `setup.sh` on the cluster, putting it into the broken/incomplete state the question describes.
3. Work the problem in the **terminal** (`/terminal/`, a full `bash` session on the controlplane). `kubectl`, `helm`, `etcdctl`, `crictl` are all available. Workers are reachable with `ssh node01` / `ssh node02`.
4. **Check Answer** - runs `validate.sh`, which inspects real cluster/API/filesystem state (not YAML syntax) and returns pass/fail with a specific reason.

### Server API

The Go exam server exposes a small REST API, useful if you want to script against it:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/status` | Server mode and health |
| `GET` | `/api/session` | Current exam session, if any |
| `POST` | `/api/session/start` | Start a session - body: `{"profile":"cka","duration_secs":7200}` |
| `POST` | `/api/session/end` | End the current session |
| `GET` | `/api/questions` | List questions for the active profile |
| `POST` | `/api/questions/{id}/setup` | Run that question's `setup.sh` |
| `POST` | `/api/questions/{id}/check` | Run that question's `validate.sh`, return pass/fail |

## Architecture

```
Browser
  │
  ▼ :80
nginx (host)
  ├── /           → K16S exam server  :8080
  └── /terminal/  → ttyd              :7681

Host VM  (Debian 13, kubeadm controlplane)
  ├── node01  (Incus LXC, Debian 12, kubelet + containerd)
  └── node02  (Incus LXC, Debian 12, kubelet + containerd)
```

| Component | Detail |
|---|---|
| Kubernetes | v1.33.x via kubeadm |
| CNI | Calico (VXLAN), enforces NetworkPolicy |
| Metrics | [metrics-server](https://github.com/kubernetes-sigs/metrics-server), `kubectl top` works out of the box |
| Worker nodes | Incus LXC containers, full systemd, `/dev/kmsg`, containerd |
| Terminal | [ttyd](https://github.com/tsl0922/ttyd), running as `root` on the controlplane |
| Exam server | Go binary + SvelteKit frontend, reads question YAML from disk at startup |

### Laptop mode (Lima)

Identical stack, just relocated: the "Host VM" is a local Lima VM (Ubuntu 24.04) managed by `local/k16s-local`, with nginx's port 80 forwarded to `localhost:8080`. The controlplane/worker split, kubeadm, and Incus are unchanged - it's the same real cluster, running on your hardware instead of rented hardware.

### Lightweight mode (kind)

Swaps the VM and Incus for [kind](https://kind.sigs.k8s.io): the "Host VM" becomes the kind control-plane container, and `node01`/`node02` become kind worker containers. kubeadm, static pods, etcd, and Calico are unchanged underneath. The one fidelity gap: AppArmor is unavailable, since Docker doesn't expose kernel securityfs to containers.

### Runtime files (VPS/host and laptop modes)

```
/etc/k16s/
  kubeadm-init.yaml      kubeadm init config
  join-command.sh        raw kubeadm join command (token valid 24h)
  candidate-password     candidate user password (mode 600)

/var/lib/k16s/
  markers/               idempotency markers (<step>.done files)
  exams/                 exam question data, copied from repo exams/

/etc/systemd/system/
  k16s-terminal.service  ttyd on 127.0.0.1:7681
  k16s-desktop.service   noVNC desktop (VPS mode; laptop mode with --desktop)
  k16s-server.service    exam server on 127.0.0.1:8080

/etc/nginx/sites-available/k16s   nginx config
/etc/sudoers.d/candidate          limited kubectl/etcdctl sudo for the candidate user
```

### Candidate environment

- User: `candidate` (uid 1000)
- Shell: bash, with kubectl completion, a `k` alias, vim/tmux config
- kubeconfig: `/home/candidate/.kube/config`
- `ssh node01` / `ssh node02` - key-based, root inside each worker container
- `ssh controlplane` → the host itself, for tasks that need host-level access

### Key versions

| Component | Version |
|---|---|
| Kubernetes | v1.33.x |
| Calico | v3.29.1 (Tigera operator, VXLAN) |
| containerd | 2.x |
| ttyd | 1.7.7 |
| etcdctl | v3.5.17 |
| metrics-server | v0.9.0 |
| Incus container image | `images:debian/12` |

Pod CIDR: `10.244.0.0/16`. Service CIDR: `10.96.0.0/12`. Incus bridge `incusbr0`: `10.10.0.1/24`, with `node01` at `10.10.0.11` and `node02` at `10.10.0.12`.

## Adding custom questions

Each question is one YAML file plus two scripts:

```
exams/<profile>/
  01-my-question.yaml
  scripts/01-my-question/
    setup.sh                   # puts the cluster in the broken/incomplete state
    validate.sh                # checks the cluster; exit 0 = PASS, exit 1 = FAIL
```

YAML fields:

| Field | Meaning |
|---|---|
| `id` | Matches the filename stem and the `scripts/<id>/` directory |
| `title` | Shown in the exam UI |
| `weight` | Relative scoring weight |
| `context` | `controlplane` if the question needs host-level access; omit otherwise |
| `description` | Full question text, Markdown, shown to the candidate |
| `hint` | Shown when the candidate asks for a hint |
| `requires` | Set to `heavy` if the question needs a capability lightweight mode can't provide (e.g. AppArmor). Excludes it from lightweight-mode scoring |

After adding files, re-run `bash install.sh --host <ip>` (or the equivalent for your mode) to sync and restart the server. No rebuild needed - the Go binary reads YAML from disk at startup.

## Troubleshooting

**Nodes show `NotReady` after restarting a VPS/VM.** Incus containers don't always restart in sync with `kubelet`/`incusd` right after a reboot. Check `incus list` - if `node01`/`node02` show `STOPPED`, run `incus start node01 node02`. Give it 10-15 seconds, then `kubectl get nodes` should show everything `Ready`.

**Lost the SSH tunnel** (public `--host` target, laptop slept or connection dropped). Reconnect without re-running the installer:

```bash
./k16s-tunnel status <ip>
./k16s-tunnel up <ip>
```

**AppArmor questions are struck through / blocked.** Expected in lightweight mode, Docker doesn't expose kernel securityfs to containers. Use `--laptop` or `--host` if you need those 8 questions.

**`kubectl top` returns nothing.** metrics-server needs a minute to collect its first data point after the cluster comes up. Wait, then retry.

## Uninstalling

```bash
bash uninstall.sh                        # on the VM directly - asks for confirmation
bash uninstall.sh --yes                  # skip the confirmation prompt
bash uninstall.sh --host <ip>            # remote, same targeting as install.sh --host
bash uninstall.sh --laptop               # deletes the whole Lima VM, nothing else to clean up
bash uninstall.sh --lightweight          # deletes the whole kind cluster - same story
bash uninstall.sh --dry-run              # print what would be removed, touch nothing (VPS/host mode only)
```

Laptop and lightweight mode are a clean teardown by construction: deleting the Lima VM's disk, or the kind cluster, removes everything K16S ever touched.

For VPS/host mode, `uninstall.sh` removes the kubeadm cluster, every Incus worker container, every package K16S installed, the candidate user, and `/var/lib/k16s` + `/etc/k16s`. It only removes tools it can prove it installed - if etcdctl, Helm, Go, or Node.js were already on the machine before K16S ran, they're left alone. If K16S changed the hostname or disabled swap, both are restored. The SSH tunnel, if one was opened, is closed too.
