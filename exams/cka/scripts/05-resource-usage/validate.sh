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

# Verify top-cpu-pod is a real pod name
CPU_POD=$(cat /opt/cka/top-cpu-pod.txt | tr -d '[:space:]')
if ! kubectl get pods -A --no-headers 2>/dev/null | awk '{print $2}' | grep -qx "$CPU_POD"; then
  echo "FAIL: '$CPU_POD' in top-cpu-pod.txt is not a valid pod name"
  exit 1
fi

# Verify top-mem-pod is a real pod name
MEM_POD=$(cat /opt/cka/top-mem-pod.txt | tr -d '[:space:]')
if ! kubectl get pods -A --no-headers 2>/dev/null | awk '{print $2}' | grep -qx "$MEM_POD"; then
  echo "FAIL: '$MEM_POD' in top-mem-pod.txt is not a valid pod name"
  exit 1
fi

# Verify top-cpu-node is a real node name
CPU_NODE=$(cat /opt/cka/top-cpu-node.txt | tr -d '[:space:]')
if ! kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CPU_NODE"; then
  echo "FAIL: '$CPU_NODE' in top-cpu-node.txt is not a valid node name"
  exit 1
fi

# Verify CPU pod is actually the top CPU consumer
ACTUAL_TOP=$(kubectl top pods -A --sort-by=cpu --no-headers 2>/dev/null | head -1 | awk '{print $2}')
if [[ "$CPU_POD" != "$ACTUAL_TOP" ]]; then
  echo "FAIL: top-cpu-pod.txt says '$CPU_POD' but actual top-CPU pod is '$ACTUAL_TOP'"
  exit 1
fi

echo "PASS: top-cpu-pod=$CPU_POD, top-mem-pod=$MEM_POD, top-cpu-node=$CPU_NODE all correct"
