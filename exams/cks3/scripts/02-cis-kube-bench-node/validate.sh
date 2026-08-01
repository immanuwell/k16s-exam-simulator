#!/usr/bin/env bash
set -eo pipefail

if [[ ! -s /opt/cks3-cis/kube-bench-node.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kube-bench-node.txt is missing or empty"
  exit 1
fi

if ! grep -q "^\[INFO\]\|^\[PASS\]\|^\[FAIL\]\|^\[WARN\]" /opt/cks3-cis/kube-bench-node.txt; then
  echo "FAIL: kube-bench-node.txt does not look like kube-bench output"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/kube-bench-node-fails.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kube-bench-node-fails.txt is missing"
  exit 1
fi

# Verify every line in the fails file corresponds to an actual FAIL in the output
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! grep -q "^FAIL.*${id}" /opt/cks3-cis/kube-bench-node.txt; then
    echo "FAIL: ID '$id' in kube-bench-node-fails.txt not found as a FAIL in kube-bench-node.txt"
    exit 1
  fi
done < /opt/cks3-cis/kube-bench-node-fails.txt

ACTUAL=$(grep -c '^FAIL' /opt/cks3-cis/kube-bench-node.txt || true)
SAVED=$(grep -c '[0-9]' /opt/cks3-cis/kube-bench-node-fails.txt 2>/dev/null || true)
if [[ "$ACTUAL" != "$SAVED" ]]; then
  echo "FAIL: fails file has $SAVED entries but output has $ACTUAL FAIL lines"
  exit 1
fi

echo "PASS: kube-bench node output saved; all $SAVED FAIL IDs recorded correctly"
