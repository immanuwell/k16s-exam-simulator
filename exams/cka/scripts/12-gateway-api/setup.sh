#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p /opt/cka

# Install Gateway API CRDs (standard channel)
if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
  echo "Gateway API CRDs installed"
else
  echo "Gateway API CRDs already present"
fi

kubectl create namespace gateway-demo --dry-run=client -o yaml | kubectl apply -f -

# Create two backend services
kubectl -n gateway-demo create deployment svc-a-deploy --image=nginx:alpine \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway-demo create deployment svc-b-deploy --image=nginx:alpine \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n gateway-demo expose deployment svc-a-deploy \
  --name=svc-a --port=80 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway-demo expose deployment svc-b-deploy \
  --name=svc-b --port=80 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "gateway-demo namespace ready with svc-a and svc-b; Gateway API CRDs installed"
