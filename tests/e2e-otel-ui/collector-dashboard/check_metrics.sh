#!/usr/bin/env bash
#
# Wait until every series that the "OpenTelemetry Collector" dashboard queries is present in the
# OpenShift monitoring stack (Thanos querier), so that the UI specs only start once the data exists.
#
# Adapted from opentelemetry-operator tests/e2e-openshift/monitoring/check_metrics.sh. Differences:
# the wait is bounded, only the dashboard's series are checked (scoped to $NAMESPACE) and the
# temporary RBAC objects are removed on exit.
#
# Environment:
#   NAMESPACE                 namespace with the collectors (set by Chainsaw)
#   METRICS_TIMEOUT_SECONDS   overall timeout, default 420

set -uo pipefail

: "${NAMESPACE:?NAMESPACE must be set}"
TIMEOUT="${METRICS_TIMEOUT_SECONDS:-420}"
SA=e2e-test-metrics-reader

cleanup() {
  oc adm policy remove-cluster-role-from-user cluster-monitoring-view "system:serviceaccount:${NAMESPACE}:${SA}" >/dev/null 2>&1 || true
  oc delete serviceaccount "$SA" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

oc create serviceaccount "$SA" -n "$NAMESPACE" || exit 1
oc adm policy add-cluster-role-to-user cluster-monitoring-view "system:serviceaccount:${NAMESPACE}:${SA}" || exit 1

TOKEN=$(oc create token "$SA" -n "$NAMESPACE") || exit 1
THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}') || exit 1

# The series behind the nine panels and the dashboard variables. The label matchers mirror the
# dashboard queries: the `namespace` label comes from the scrape target, `service` is the
# `<cr>-collector-monitoring` Service.
queries=(
  "otelcol_receiver_accepted_metric_points{namespace=\"${NAMESPACE}\"}"
  "otelcol_receiver_accepted_spans{namespace=\"${NAMESPACE}\"}"
  "otelcol_exporter_sent_metric_points{namespace=\"${NAMESPACE}\"}"
  "otelcol_exporter_sent_spans{namespace=\"${NAMESPACE}\"}"
  "otelcol_exporter_send_failed_metric_points{namespace=\"${NAMESPACE}\"}"
  "otelcol_exporter_send_failed_spans{namespace=\"${NAMESPACE}\"}"
  "otelcol_processor_memory_limiter_accepted_metric_points{namespace=\"${NAMESPACE}\"}"
  "otelcol_processor_memory_limiter_accepted_spans{namespace=\"${NAMESPACE}\"}"
  "otelcol_process_memory_rss{namespace=\"${NAMESPACE}\",service=\"cluster-collector-collector-monitoring\"}"
  "otelcol_process_memory_rss{namespace=\"${NAMESPACE}\",service=\"second-collector-monitoring\"}"
  "otelcol_process_runtime_heap_alloc_bytes{namespace=\"${NAMESPACE}\",service=\"cluster-collector-collector-monitoring\"}"
  "otelcol_process_runtime_heap_alloc_bytes{namespace=\"${NAMESPACE}\",service=\"second-collector-monitoring\"}"
  "otelcol_process_cpu_seconds{namespace=\"${NAMESPACE}\",service=\"cluster-collector-collector-monitoring\"}"
  "target_info{namespace=\"${NAMESPACE}\"}"
)

deadline=$((SECONDS + TIMEOUT))
missing=()
for query in "${queries[@]}"; do
  while true; do
    # -k: the route is served with the cluster's self-signed ingress certificate (as the console is, see
    # ignoreHTTPSErrors in ui/playwright.config.ts). The token is short-lived, only has cluster-monitoring-view
    # and its service account is removed on exit.
    response=$(curl -sk --max-time 20 -H "Authorization: Bearer ${TOKEN}" \
      --data-urlencode "query=${query}" "https://${THANOS_QUERIER_HOST}/api/v1/query" || true)
    count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo 0)

    if [[ "${count:-0}" -gt 0 ]]; then
      echo "Series present: ${query}"
      break
    fi

    if (( SECONDS >= deadline )); then
      echo "Timed out after ${TIMEOUT}s waiting for series: ${query}"
      echo "Last response: ${response}"
      missing+=("$query")
      break
    fi

    echo "No series yet for ${query}, retrying..."
    sleep 5
  done

  if (( ${#missing[@]} > 0 )); then
    break
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Dashboard series missing from the monitoring stack: ${missing[*]}"
  echo "--- ServiceMonitors and pods in ${NAMESPACE}"
  oc get servicemonitor,pods -n "$NAMESPACE" || true
  echo "--- user workload monitoring pods"
  oc get pods -n openshift-user-workload-monitoring || true
  exit 1
fi

echo "All dashboard series are present."
