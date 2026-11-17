#!/bin/bash
# Verify in CloudWatch that platform metrics (up from node-exporter, kube_pod_info) and user
# workload metrics (avalanche counters from the sample application) arrived through remote
# write v2 and the AWS EMF exporter during this test run, and that both Prometheus instances
# report no failed samples.
set -uo pipefail
region="us-east-2"
cw_namespace="Tracing-OCP-Monitoring"

# Fetch AWS credentials based on CLUSTER_PROFILE_DIR variable
if [ -n "${CLUSTER_PROFILE_DIR:-}" ]; then
    AWS_ACCESS_KEY_ID=$(sed -n 's/^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
    AWS_SECRET_ACCESS_KEY=$(sed -n 's/^[[:space:]]*aws_secret_access_key[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
elif oc get secret aws-creds -n kube-system >/dev/null 2>&1; then
    AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d)
    AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d)
elif aws sts get-caller-identity >/dev/null 2>&1; then
    # keep the credentials that the AWS CLI already resolves (environment, profile, SSO or role)
    use_cli_credentials=true
else
    echo "No AWS credentials found (CLUSTER_PROFILE_DIR, aws-creds secret in kube-system, or AWS CLI configuration)"
    exit 1
fi
if [ "${use_cli_credentials:-false}" != true ]; then
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "FAIL: the AWS credentials are empty"
        exit 1
    fi
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi
export AWS_DEFAULT_REGION=${region}
export AWS_PAGER=""
# from here on a failing aws or oc command fails the test instead of producing a misleading message
set -e

# Only data points published since this test run started count: list-metrics would also
# return metrics that an earlier run published up to two weeks ago. The run start is the
# creation time of the sample application. The metrics searched are the OTelLib + service.name
# rollups that the EMF exporter creates with ZeroAndSingleDimensionRollup.
run_start=$(oc get deployment metrics-sample-app -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}')
if [ -z "$run_start" ]; then
  echo "FAIL: could not determine the start of the test run"
  exit 1
fi
found_metric() { # metric name, dimension name, dimension value
  local search count
  search="SEARCH('{${cw_namespace},OTelLib,$2} MetricName=\"$1\" \"$2\"=\"$3\"', 'SampleCount', 60)"
  count=$(aws cloudwatch get-metric-data --region "$region" --start-time "$run_start" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --metric-data-queries "[{\"Id\":\"q\",\"Expression\":$(printf '%s' "$search" | jq -R .),\"Period\":60}]" \
    --query 'sum(MetricDataResults[].length(Values))' --output text 2>/dev/null) || return 1
  [ -n "$count" ] && [ "$count" != "None" ] && [ "$count" -gt 0 ] 2>/dev/null
}

# the platform Prometheus needs a few minutes before it sends after the config reload, and
# CloudWatch lists new metrics with a delay; stop well before the 15 minute step timeout
deadline=$(( $(date +%s) + 600 ))
# the Prometheus checks at the end get until a minute before the 15 minute step timeout
prometheus_deadline=$(( $(date +%s) + 840 ))
attempt=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  attempt=$((attempt + 1))
  echo "Attempt $attempt: looking for data points published since $run_start in the CloudWatch namespace $cw_namespace"
  if found_metric up service.name node-exporter && found_metric kube_pod_info service.name kube-state-metrics && found_metric avalanche_counter_metric_mmmmm_0_0_total service.name metrics-sample-app; then
    echo "Platform metrics (up, kube_pod_info) and user workload metrics (avalanche_counter_metric_mmmmm_0_0_total) are in CloudWatch."
    break
  fi
  sleep 10
done
if ! found_metric up service.name node-exporter || ! found_metric kube_pod_info service.name kube-state-metrics || ! found_metric avalanche_counter_metric_mmmmm_0_0_total service.name metrics-sample-app; then
  echo "FAIL: expected metrics with data points from this run not found in CloudWatch namespace $cw_namespace"
  exit 1
fi

# The EMF log stream carries the raw records
STREAMS=$(aws logs describe-log-streams --log-group-name "$log_group_name" --log-stream-name-prefix "$log_stream_name" --region "$region" --query 'logStreams[].logStreamName' --output text)
if [[ "$STREAMS" == *"$log_stream_name"* ]]; then
  echo "EMF log stream $log_stream_name exists in log group $log_group_name"
else
  echo "FAIL: EMF log stream $log_stream_name not found in log group $log_group_name"
  exit 1
fi

# Prometheus side: both instances send, nothing failed
oc create serviceaccount e2e-test-metrics-reader -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-cluster-role-to-user cluster-monitoring-view "system:serviceaccount:$NAMESPACE:e2e-test-metrics-reader"
TOKEN=$(oc create token e2e-test-metrics-reader -n "$NAMESPACE")
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
# Prints the first result value, "none" when the query has no result, or "error" when the
# query itself failed (unreachable route, rejected token, bad response).
query() {
  local response
  response=$(curl -sk -H "Authorization: Bearer $TOKEN" --data-urlencode "query=$1" "https://$THANOS_QUERIER_HOST/api/v1/query") || true
  if ! echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
    echo "error"
    return
  fi
  echo "$response" | jq -r '.data.result[0].value[1] // "none"'
}
for instance in prometheus-k8s prometheus-user-workload; do
  # the remote write metrics of a Prometheus that just started appear in Thanos Querier only after
  # the next scrapes, so poll for them as prometheusremotewritereceiver-cluster-monitoring does
  while [ "$(date +%s)" -lt "$prometheus_deadline" ]; do
    sent=$(query "sum(rate(prometheus_remote_storage_samples_total{pod=~\"${instance}-.*\",remote_name=\"otel\"}[5m]))")
    if [[ "$sent" != "none" && "$sent" != "error" ]] && awk "BEGIN{exit !($sent > 0)}"; then
      break
    fi
    echo "$instance: no remote write throughput yet ($sent), retrying..."
    sleep 10
  done
  if [[ "$sent" == "none" || "$sent" == "error" ]] || ! awk "BEGIN{exit !($sent > 0)}"; then
    echo "FAIL: $instance does not send samples to the collector ($sent)"
    exit 1
  fi
  echo "$instance sends $sent samples/s to the collector"
  # samples_dropped_total counts the samples removed by writeRelabelConfigs, so only failed samples matter
  value=$(query "sum(prometheus_remote_storage_samples_failed_total{pod=~\"${instance}-.*\",remote_name=\"otel\"})")
  if [[ "$value" == "error" ]]; then
    echo "FAIL: could not query prometheus_remote_storage_samples_failed_total for $instance through Thanos Querier"
    exit 1
  fi
  if [[ "$value" != "none" && "$value" != "0" ]]; then
    echo "FAIL: $instance reports prometheus_remote_storage_samples_failed_total=$value"
    exit 1
  fi
done
echo "OpenShift monitoring metrics were exported to AWS CloudWatch via remote write v2 and the AWS EMF exporter."
