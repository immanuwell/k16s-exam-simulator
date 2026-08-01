#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get serviceaccount pod-reader -n rbac-demo >/dev/null 2>&1 || {
  echo "FAIL: ServiceAccount pod-reader not found in rbac-demo"
  exit 1
}

kubectl get role pod-reader-role -n rbac-demo >/dev/null 2>&1 || {
  echo "FAIL: Role pod-reader-role not found in rbac-demo"
  exit 1
}

kubectl get rolebinding pod-reader-binding -n rbac-demo >/dev/null 2>&1 || {
  echo "FAIL: RoleBinding pod-reader-binding not found in rbac-demo"
  exit 1
}

# Check role rules include pods get/list/watch
VERBS=$(kubectl get role pod-reader-role -n rbac-demo -o jsonpath='{.rules[*].verbs}' 2>/dev/null)
for v in get list watch; do
  if ! echo "$VERBS" | grep -q "$v"; then
    echo "FAIL: Role pod-reader-role missing verb '$v'"
    exit 1
  fi
done

# SA must be able to get pods
CAN_GET=$(kubectl auth can-i get pods \
  --as=system:serviceaccount:rbac-demo:pod-reader \
  -n rbac-demo 2>/dev/null)
if [[ "$CAN_GET" != "yes" ]]; then
  echo "FAIL: pod-reader cannot get pods (got: $CAN_GET)"
  exit 1
fi

# SA must NOT be able to get secrets
CAN_SECRET=$(kubectl auth can-i get secrets \
  --as=system:serviceaccount:rbac-demo:pod-reader \
  -n rbac-demo 2>/dev/null)
if [[ "$CAN_SECRET" != "no" ]]; then
  echo "FAIL: pod-reader can get secrets — permissions too broad (got: $CAN_SECRET)"
  exit 1
fi

if [[ ! -f /opt/cka/rbac-check.txt ]]; then
  echo "FAIL: /opt/cka/rbac-check.txt not saved"
  exit 1
fi

if ! grep -q '^no' /opt/cka/rbac-check.txt; then
  echo "FAIL: rbac-check.txt should contain 'no' (pod-reader cannot get secrets)"
  exit 1
fi

echo "PASS: RBAC setup correct — pod-reader can get pods, cannot get secrets"
