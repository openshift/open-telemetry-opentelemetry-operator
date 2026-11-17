#!/bin/bash
# Delete the CloudWatch log group created by the AWS exporters of the test collector. A log group that does not
# exist is fine; any other error fails the cleanup so that it is noticed.
set -uo pipefail
region="us-east-2"
if [ -n "${CLUSTER_PROFILE_DIR:-}" ]; then
  export AWS_SHARED_CREDENTIALS_FILE="$CLUSTER_PROFILE_DIR/.awscred"
elif oc get secret aws-creds -n kube-system >/dev/null 2>&1; then
  access_key_id=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d) || access_key_id=""
  secret_access_key=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d) || secret_access_key=""
  if [ -z "$access_key_id" ] || [ -z "$secret_access_key" ]; then
    echo "FAIL: could not read the aws-creds secret in kube-system"
    exit 1
  fi
  export AWS_ACCESS_KEY_ID="$access_key_id" AWS_SECRET_ACCESS_KEY="$secret_access_key"
fi
export AWS_PAGER=""
# Delete the collector first and wait for its pods to stop: a collector that still runs can flush
# one more batch after the log group is gone, and the exporter then creates the log group again.
collector="${collector:-cwlogs}"
if ! oc delete opentelemetrycollector "$collector" -n "$NAMESPACE" --ignore-not-found --wait=true; then
  echo "FAIL: could not delete the collector $collector"
  exit 1
fi
# Delete the log group only after a successful pod listing returned no collector pod.
stopped=false
for i in $(seq 1 30); do
  if pods=$(oc get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${NAMESPACE}.${collector}" -o name); then
    if [ -z "$pods" ]; then
      stopped=true
      break
    fi
  else
    echo "Listing the collector pods failed, retrying..."
  fi
  sleep 2
done
if [ "$stopped" != true ]; then
  echo "FAIL: the pods of the collector $collector did not stop, so the log group $log_group_name is not deleted"
  exit 1
fi
if output=$(aws logs delete-log-group --log-group-name "$log_group_name" --region "$region" 2>&1); then
  echo "Log group $log_group_name deleted"
elif echo "$output" | grep -q 'ResourceNotFoundException'; then
  echo "Log group $log_group_name does not exist"
else
  echo "FAIL: could not delete log group $log_group_name: $output"
  exit 1
fi
