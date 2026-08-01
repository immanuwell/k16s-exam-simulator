#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

DEPLOY="web-aa"
PROFILE="k8s-no-proc-write"
CTR="web"

# Check deployment exists and is ready
READY=$(kubectl get deployment "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
DESIRED=$(kubectl get deployment "$DEPLOY" -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [[ "$READY" != "$DESIRED" || -z "$READY" ]]; then
  echo "FAIL: deployment $DEPLOY is not fully ready (${READY:-0}/$DESIRED replicas)"
  exit 1
fi

# Check AppArmor annotation or native field on the pod template
TMPL=$(kubectl get deployment "$DEPLOY" -o json | python3 -c "
import sys,json
d=json.load(sys.stdin)
import json as j
print(j.dumps(d['spec']['template']))
")

if ! python3 -c "
import sys,json
d=json.loads('''$TMPL'''.replace(\"'\",\"'\"))
" 2>/dev/null; then
  TMPL=$(kubectl get deployment "$DEPLOY" -o jsonpath='{.spec.template}' 2>/dev/null)
fi

DEPLOY_JSON=$(kubectl get deployment "$DEPLOY" -o json)

if ! python3 -c "
import sys,json
d=json.load(sys.stdin)
profile='$PROFILE'
ctr_name='$CTR'
tmpl=d['spec']['template']

# Check annotation
ann=tmpl.get('metadata',{}).get('annotations',{})
key='container.apparmor.security.beta.kubernetes.io/'+ctr_name
ann_match=(ann.get(key)=='localhost/'+profile)

# Check native securityContext on container
ctrs=tmpl.get('spec',{}).get('containers',[])
native_match=any(
  c.get('name')==ctr_name and
  c.get('securityContext',{}).get('appArmorProfile',{}).get('localhostProfile')==profile
  for c in ctrs
)

assert ann_match or native_match, \
  f'AppArmor profile {profile} not found on container {ctr_name} in deployment template. ann={ann}, ctrs={[c.get(\"name\") for c in ctrs]}'
print('ok')
" <<< "$DEPLOY_JSON" 2>/dev/null | grep -q ok; then
  echo "FAIL: deployment $DEPLOY does not have AppArmor profile $PROFILE on container $CTR"
  exit 1
fi

if [[ ! -f /opt/cks-apparmor/web-aa.yaml ]]; then
  echo "FAIL: deployment manifest not saved to /opt/cks-apparmor/web-aa.yaml"
  exit 1
fi

echo "PASS: deployment web-aa has AppArmor profile k8s-no-proc-write on container web; rollout complete"
