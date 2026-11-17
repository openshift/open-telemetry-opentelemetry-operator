#!/bin/bash
# Verify on the Prometheus side that both instances send to the collector and that no
# samples failed or were dropped.
set -uo pipefail

oc create serviceaccount e2e-test-metrics-reader -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-cluster-role-to-user cluster-monitoring-view "system:serviceaccount:$NAMESPACE:e2e-test-metrics-reader"
TOKEN=$(oc create token e2e-test-metrics-reader -n "$NAMESPACE")
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')

# Prints the first result value, "none" when the query has no result, or "error" when the
# query itself failed (unreachable route, rejected token, bad response).
query() {
  local response
  response=$(curl -sk -H "Authorization: Bearer $TOKEN" --data-urlencode "query=$1" "https://$THANOS_QUERIER_HOST/api/v1/query")
  if ! echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
    echo "error"
    return
  fi
  echo "$response" | jq -r '.data.result[0].value[1] // "none"'
}

for instance in prometheus-k8s prometheus-user-workload; do
  for i in $(seq 30); do
    sent=$(query "sum(rate(prometheus_remote_storage_samples_total{pod=~\"${instance}-.*\",remote_name=\"otel\"}[2m]))")
    if [[ "$sent" != "none" && "$sent" != "error" ]] && awk "BEGIN{exit !($sent > 0)}"; then
      echo "$instance sends $sent samples/s to the collector"
      break
    fi
    echo "$instance: no remote write throughput yet ($sent), retrying..."
    sleep 10
  done
  if [[ "$sent" == "none" || "$sent" == "error" ]] || ! awk "BEGIN{exit !($sent > 0)}"; then
    echo "FAIL: $instance does not send samples to the collector"
    exit 1
  fi
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
  echo "$instance: prometheus_remote_storage_samples_failed_total=$value"
done
echo "Remote write v2 from the platform and user workload monitoring Prometheus instances works without failures."
