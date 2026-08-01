#!/usr/bin/env bash
set -eo pipefail

if [[ ! -s /opt/cks3-cis/kube-bench-master.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kube-bench-master.txt is missing or empty"
  exit 1
fi

if ! grep -q "^\[INFO\]\|^\[PASS\]\|^\[FAIL\]\|^\[WARN\]" /opt/cks3-cis/kube-bench-master.txt; then
  echo "FAIL: kube-bench-master.txt does not look like kube-bench output"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/kube-bench-master-fail-count.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kube-bench-master-fail-count.txt is missing"
  exit 1
fi

COUNT=$(cat /opt/cks3-cis/kube-bench-master-fail-count.txt | tr -d '[:space:]')
if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "FAIL: kube-bench-master-fail-count.txt does not contain an integer (got: '$COUNT')"
  exit 1
fi

ACTUAL=$(grep -c '^FAIL' /opt/cks3-cis/kube-bench-master.txt || true)
if [[ "$COUNT" != "$ACTUAL" ]]; then
  echo "FAIL: fail count $COUNT does not match actual FAIL lines in output ($ACTUAL)"
  exit 1
fi

echo "PASS: kube-bench master output saved; FAIL count $COUNT is correct"
