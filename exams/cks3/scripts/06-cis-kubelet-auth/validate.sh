#!/usr/bin/env bash
set -eo pipefail

ANON=$(python3 -c "
import yaml
with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('authentication',{}).get('anonymous',{}).get('enabled', 'missing'))
")
if [[ "$ANON" != "False" && "$ANON" != "false" ]]; then
  echo "FAIL: authentication.anonymous.enabled is not false (got: $ANON)"
  exit 1
fi

MODE=$(python3 -c "
import yaml
with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('authorization',{}).get('mode', 'missing'))
")
if [[ "$MODE" != "Webhook" ]]; then
  echo "FAIL: authorization.mode is not Webhook (got: $MODE)"
  exit 1
fi

if [[ ! -f /opt/cks3-cis/kubelet-auth.txt ]]; then
  echo "FAIL: /opt/cks3-cis/kubelet-auth.txt is missing"
  exit 1
fi

if ! grep -q 'enabled\|anonymous' /opt/cks3-cis/kubelet-auth.txt || \
   ! grep -q 'mode\|authorization' /opt/cks3-cis/kubelet-auth.txt; then
  echo "FAIL: kubelet-auth.txt must contain both the anonymous and mode lines"
  exit 1
fi

echo "PASS: kubelet anonymous auth disabled, authorization mode=Webhook; file saved"
