#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD=$(kubectl get pod log-sidecar -n sidecar-demo -o json 2>/dev/null) || {
  echo "FAIL: pod log-sidecar not found in sidecar-demo"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod log-sidecar is not Running (phase: $PHASE)"
  exit 1
fi

# Must have exactly 2 containers
CONTAINER_COUNT=$(echo "$POD" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['spec']['containers']))")
if [[ "$CONTAINER_COUNT" -ne 2 ]]; then
  echo "FAIL: expected 2 containers, found $CONTAINER_COUNT"
  exit 1
fi

# Container names must be app and log-shipper
NAMES=$(echo "$POD" | python3 -c "
import sys,json
names=[c['name'] for c in json.load(sys.stdin)['spec']['containers']]
print(' '.join(sorted(names)))
")
if ! echo "$NAMES" | grep -q 'app' || ! echo "$NAMES" | grep -q 'log-shipper'; then
  echo "FAIL: containers must be named 'app' and 'log-shipper' (found: $NAMES)"
  exit 1
fi

# Both containers must mount the same emptyDir volume
SHARED_VOL=$(echo "$POD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
vols={v['name'] for v in d['spec'].get('volumes',[]) if 'emptyDir' in v}
if not vols: print('no-emptydir'); sys.exit(0)
for vname in vols:
    mounters=[c['name'] for c in d['spec']['containers']
              for vm in c.get('volumeMounts',[]) if vm['name']==vname]
    if len(mounters)>=2:
        print('ok'); sys.exit(0)
print('not-shared')
")
if [[ "$SHARED_VOL" != "ok" ]]; then
  echo "FAIL: emptyDir volume is not mounted in both containers ($SHARED_VOL)"
  exit 1
fi

# Sidecar must be producing log output
for i in {1..6}; do
  LOGS=$(kubectl logs log-sidecar -c log-shipper -n sidecar-demo 2>/dev/null | wc -l | tr -d ' ')
  [[ "$LOGS" -gt 0 ]] && break
  sleep 5
done
if [[ "$LOGS" -eq 0 ]]; then
  echo "FAIL: log-shipper container has no log output — shared volume may not be working"
  exit 1
fi

if [[ ! -f /opt/cka/log-sidecar.yaml ]]; then
  echo "FAIL: /opt/cka/log-sidecar.yaml not saved"
  exit 1
fi

echo "PASS: pod log-sidecar Running with app+log-shipper sharing emptyDir; sidecar producing logs; YAML saved"
