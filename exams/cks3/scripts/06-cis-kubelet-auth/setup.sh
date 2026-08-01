#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

# Ensure a bad state for the candidate to fix
python3 - <<'EOF'
import yaml, sys

with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)

cfg.setdefault('authentication', {}).setdefault('anonymous', {})['enabled'] = True
cfg.setdefault('authorization', {})['mode'] = 'AlwaysAllow'

with open('/var/lib/kubelet/config.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
EOF

systemctl restart kubelet || true

echo "Environment ready — fix kubelet authentication and authorization settings"
