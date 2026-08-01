#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

[[ -f /opt/cka2/events.txt ]] || {
  echo "FAIL: /opt/cka2/events.txt not found"
  exit 1
}

[[ -f /opt/cka2/warning-events.txt ]] || {
  echo "FAIL: /opt/cka2/warning-events.txt not found"
  exit 1
}

[[ -f /opt/cka2/pod-failure-reason.txt ]] || {
  echo "FAIL: /opt/cka2/pod-failure-reason.txt not found"
  exit 1
}

# events.txt must contain events from event-demo namespace
if ! grep -qi 'event-demo\|problem-pod\|NAMESPACE\|Warning\|Normal' /opt/cka2/events.txt; then
  echo "FAIL: /opt/cka2/events.txt does not look like kubectl get events output"
  exit 1
fi

# pod-failure-reason.txt must mention the pull failure
if ! grep -qi 'Back\|Pull\|Failed\|Err' /opt/cka2/pod-failure-reason.txt; then
  echo "FAIL: /opt/cka2/pod-failure-reason.txt does not contain a failure reason (e.g. ErrImagePull, ImagePullBackOff)"
  exit 1
fi

echo "PASS: events.txt, warning-events.txt, and pod-failure-reason.txt all saved with correct content"
