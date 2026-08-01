#!/usr/bin/env bash
set -eo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

# Check Job
JOB=$(kubectl get job db-backup -n batch-demo -o json 2>/dev/null) || {
  echo "FAIL: Job db-backup not found in batch-demo"
  exit 1
}

SUCCEEDED=$(echo "$JOB" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('status', {}).get('succeeded', 0))
")
if [[ "${SUCCEEDED:-0}" -lt 1 ]]; then
  # Give it more time if still running
  echo "Waiting for Job to complete..."
  kubectl wait --for=condition=complete job/db-backup -n batch-demo --timeout=60s 2>/dev/null || {
    echo "FAIL: Job db-backup did not complete (succeeded=$SUCCEEDED)"
    exit 1
  }
fi

BACKOFF=$(echo "$JOB" | python3 -c "
import sys, json
print(json.load(sys.stdin)['spec'].get('backoffLimit', 'missing'))
")
if [[ "$BACKOFF" != "2" ]]; then
  echo "FAIL: Job backoffLimit is $BACKOFF (expected 2)"
  exit 1
fi

# Check CronJob
CJ=$(kubectl get cronjob cleanup-logs -n batch-demo -o json 2>/dev/null) || {
  echo "FAIL: CronJob cleanup-logs not found in batch-demo"
  exit 1
}

SCHEDULE=$(echo "$CJ" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['schedule'])")
if [[ "$SCHEDULE" != "*/5 * * * *" ]]; then
  echo "FAIL: CronJob schedule is '$SCHEDULE' (expected '*/5 * * * *')"
  exit 1
fi

SUCCESS_HIST=$(echo "$CJ" | python3 -c "
import sys, json
print(json.load(sys.stdin)['spec'].get('successfulJobsHistoryLimit', 'missing'))
")
if [[ "$SUCCESS_HIST" != "3" ]]; then
  echo "FAIL: successfulJobsHistoryLimit is $SUCCESS_HIST (expected 3)"
  exit 1
fi

[[ -f /opt/cka2/job-status.txt ]] || {
  echo "FAIL: /opt/cka2/job-status.txt not saved"
  exit 1
}

echo "PASS: Job db-backup completed (backoffLimit=2); CronJob cleanup-logs schedule=*/5 * * * * (successfulHistory=3)"
