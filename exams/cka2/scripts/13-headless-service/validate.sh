#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

SVC=$(kubectl get service db-headless -n headless-demo -o json 2>/dev/null) || {
  echo "FAIL: Service db-headless not found in headless-demo"
  exit 1
}

CLUSTER_IP=$(echo "$SVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('clusterIP','missing'))")
if [[ "$CLUSTER_IP" != "None" ]]; then
  echo "FAIL: Service db-headless clusterIP is '$CLUSTER_IP' (must be 'None' for headless)"
  exit 1
fi

PORT=$(echo "$SVC" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['ports'][0].get('port','missing'))")
if [[ "$PORT" != "80" ]]; then
  echo "FAIL: Service db-headless port is $PORT (expected 80)"
  exit 1
fi

STS=$(kubectl get statefulset db -n headless-demo -o json 2>/dev/null) || {
  echo "FAIL: StatefulSet db not found in headless-demo"
  exit 1
}

SVC_NAME=$(echo "$STS" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('serviceName','missing'))")
if [[ "$SVC_NAME" != "db-headless" ]]; then
  echo "FAIL: StatefulSet db serviceName is '$SVC_NAME' (must be 'db-headless')"
  exit 1
fi

REPLICAS=$(echo "$STS" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('replicas',0))")
if [[ "$REPLICAS" -lt 2 ]]; then
  echo "FAIL: StatefulSet db has $REPLICAS replicas (expected 2)"
  exit 1
fi

# Wait for pods to be ready
for i in $(seq 1 24); do
  READY=$(kubectl get statefulset db -n headless-demo \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [[ "${READY:-0}" -ge 2 ]] && break
  [[ $i -eq 24 ]] && {
    echo "FAIL: StatefulSet db only has ${READY:-0}/2 ready pods after 2 minutes"
    exit 1
  }
  sleep 5
done

[[ -f /opt/cka2/headless-svc.yaml ]] || {
  echo "FAIL: /opt/cka2/headless-svc.yaml not saved"
  exit 1
}

echo "PASS: headless Service db-headless (clusterIP=None, port=80) + StatefulSet db (serviceName=db-headless, 2 replicas)"
