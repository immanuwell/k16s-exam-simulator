#!/usr/bin/env bash
set -eo pipefail

ROP=$(python3 -c "
import yaml
with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('readOnlyPort', 'missing'))
")
if [[ "$ROP" != "0" ]]; then
  echo "FAIL: readOnlyPort is not 0 (got: $ROP)"
  exit 1
fi

PKD=$(python3 -c "
import yaml
with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('protectKernelDefaults', 'missing'))
")
if [[ "$PKD" != "True" && "$PKD" != "true" ]]; then
  echo "FAIL: protectKernelDefaults is not true (got: $PKD)"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/kubelet-readonlyport.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kubelet-readonlyport.txt is missing"
  exit 1
fi

if ! grep -q 'readOnlyPort' /opt/cks3-cis/kubelet-readonlyport.txt; then
  echo "FAIL: kubelet-readonlyport.txt does not contain readOnlyPort"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/kubelet-protect-kernel.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kubelet-protect-kernel.txt is missing"
  exit 1
fi

if ! grep -q 'protectKernelDefaults' /opt/cks3-cis/kubelet-protect-kernel.txt; then
  echo "FAIL: kubelet-protect-kernel.txt does not contain protectKernelDefaults"
  exit 1
fi

echo "PASS: kubelet readOnlyPort=0 and protectKernelDefaults=true; both files saved"
