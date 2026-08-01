#!/usr/bin/env bash
set -eo pipefail

mkdir -p /opt/cks3-cis

python3 - <<'EOF'
import yaml

with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)

cfg['readOnlyPort'] = 10255
cfg.pop('protectKernelDefaults', None)

with open('/var/lib/kubelet/config.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
EOF

systemctl restart kubelet || true

echo "Environment ready — disable readOnlyPort and enable protectKernelDefaults in kubelet config"
