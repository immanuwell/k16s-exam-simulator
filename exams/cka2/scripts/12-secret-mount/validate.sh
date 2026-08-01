#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

SECRET=$(kubectl get secret app-credentials -n secret-demo -o json 2>/dev/null) || {
  echo "FAIL: Secret app-credentials not found in secret-demo"
  exit 1
}

# Check both keys exist
HAS_USER=$(echo "$SECRET" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
val = d.get('data', {}).get('username', '')
print(base64.b64decode(val).decode() if val else 'missing')
")
HAS_PASS=$(echo "$SECRET" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
val = d.get('data', {}).get('password', '')
print(base64.b64decode(val).decode() if val else 'missing')
")

if [[ "$HAS_USER" != "admin" ]]; then
  echo "FAIL: Secret username is '$HAS_USER' (expected 'admin')"
  exit 1
fi
if [[ "$HAS_PASS" != 'S3cur3P@ss!' ]]; then
  echo "FAIL: Secret password does not match expected value"
  exit 1
fi

POD=$(kubectl get pod secret-consumer -n secret-demo -o json 2>/dev/null) || {
  echo "FAIL: Pod secret-consumer not found in secret-demo"
  exit 1
}

PHASE=$(echo "$POD" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'].get('phase',''))")
if [[ "$PHASE" != "Running" ]]; then
  echo "FAIL: pod secret-consumer is not Running (phase: $PHASE)"
  exit 1
fi

# Check env vars from secretKeyRef
ENV_OK=$(echo "$POD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
env = d['spec']['containers'][0].get('env', [])
names = {e.get('name'): e.get('valueFrom', {}).get('secretKeyRef', {}) for e in env}
if 'APP_USER' in names and names['APP_USER'].get('name') == 'app-credentials':
    if 'APP_PASS' in names and names['APP_PASS'].get('name') == 'app-credentials':
        print('ok'); exit()
print('missing')
")
if [[ "$ENV_OK" != "ok" ]]; then
  echo "FAIL: pod does not have APP_USER and APP_PASS env vars from app-credentials secret"
  exit 1
fi

# Check volume mount at /etc/creds
MOUNT_OK=$(echo "$POD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for vm in d['spec']['containers'][0].get('volumeMounts', []):
    if vm.get('mountPath') == '/etc/creds':
        print('ok'); exit()
print('missing')
")
if [[ "$MOUNT_OK" != "ok" ]]; then
  echo "FAIL: pod does not mount the secret at /etc/creds"
  exit 1
fi

[[ -f /opt/cka2/secret-consumer.txt ]] || {
  echo "FAIL: /opt/cka2/secret-consumer.txt not saved"
  exit 1
}

echo "PASS: Secret app-credentials (admin/correct password) mounted as env vars (APP_USER, APP_PASS) and as files at /etc/creds"
