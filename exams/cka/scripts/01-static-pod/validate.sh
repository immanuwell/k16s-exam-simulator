#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

POD=$(kubectl get pod -n default -l tier=frontend --field-selector spec.nodeName=controlplane \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${POD}" ]]; then
  echo "FAIL: no pod with label tier=frontend found on controlplane"
  exit 1
fi

# Must be a static pod (name ends with -controlplane)
if [[ "${POD}" != *"-controlplane" ]]; then
  echo "FAIL: pod '${POD}' does not appear to be a static pod (expected name ending in -controlplane)"
  exit 1
fi

# Must use nginx:alpine
IMAGE=$(kubectl get pod "${POD}" -n default -o jsonpath='{.spec.containers[0].image}')
if [[ "${IMAGE}" != "nginx:alpine" ]]; then
  echo "FAIL: expected image nginx:alpine, got ${IMAGE}"
  exit 1
fi

STATUS=$(kubectl get pod "${POD}" -n default -o jsonpath='{.status.phase}')
if [[ "${STATUS}" != "Running" ]]; then
  echo "FAIL: pod ${POD} is ${STATUS}, expected Running"
  exit 1
fi

echo "PASS: static pod ${POD} is Running with image nginx:alpine and label tier=frontend"
