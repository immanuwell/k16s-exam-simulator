#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

for f in top-cpu-pod top-mem-pod top-cpu-node; do
  if [[ ! -f /opt/cka/${f}.txt ]]; then
    echo "FAIL: /opt/cka/${f}.txt not found"
    exit 1
  fi
  if [[ ! -s /opt/cka/${f}.txt ]]; then
    echo "FAIL: /opt/cka/${f}.txt is empty"
    exit 1
  fi
done

CPU_POD=$(tr -d '[:space:]' < /opt/cka/top-cpu-pod.txt)
MEM_POD=$(tr -d '[:space:]' < /opt/cka/top-mem-pod.txt)
CPU_NODE=$(tr -d '[:space:]' < /opt/cka/top-cpu-node.txt)

# Captured up front rather than piped straight into head/grep -qx: a live
# kubectl process feeding a consumer that closes early (head -1 especially,
# right after the first line) can get SIGPIPE'd, which pipefail turns into
# the pipeline's exit status. On the unguarded assignment below, `set -e`
# would then abort the script with no FAIL message — a candidate's correct
# answer failing this check purely on write-timing luck, not on anything
# they did wrong. Reproduced directly during an end-to-end run, not
# theoretical: exit 141 (SIGPIPE), no output, one run in several.
ALL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null)
ALL_NODES=$(kubectl get nodes --no-headers 2>/dev/null)
TOP_PODS_BY_CPU=$(kubectl top pods -A --sort-by=cpu --no-headers 2>/dev/null)

if ! echo "$ALL_PODS" | awk '{print $2}' | grep -qx "$CPU_POD"; then
  echo "FAIL: '$CPU_POD' in top-cpu-pod.txt is not a valid pod name"
  exit 1
fi

if ! echo "$ALL_PODS" | awk '{print $2}' | grep -qx "$MEM_POD"; then
  echo "FAIL: '$MEM_POD' in top-mem-pod.txt is not a valid pod name"
  exit 1
fi

if ! echo "$ALL_NODES" | awk '{print $1}' | grep -qx "$CPU_NODE"; then
  echo "FAIL: '$CPU_NODE' in top-cpu-node.txt is not a valid node name"
  exit 1
fi

# Verify CPU pod is actually the top CPU consumer
ACTUAL_TOP=$(echo "$TOP_PODS_BY_CPU" | head -1 | awk '{print $2}')
if [[ "$CPU_POD" != "$ACTUAL_TOP" ]]; then
  echo "FAIL: top-cpu-pod.txt says '$CPU_POD' but actual top-CPU pod is '$ACTUAL_TOP'"
  exit 1
fi

echo "PASS: top-cpu-pod=$CPU_POD, top-mem-pod=$MEM_POD, top-cpu-node=$CPU_NODE all correct"
