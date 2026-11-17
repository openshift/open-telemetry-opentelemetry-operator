#!/bin/bash
# This script checks the debug exporter output of the OpenTelemetry collector for the events
# accepted by the webhook event receivers, and that rejected events did not arrive.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector,app.kubernetes.io/instance=${NAMESPACE}.webhookeventreceiver"

# Bodies that must be present exactly once.
EXPECTED=(
  '{"event":"one"}'
  '{"event":"two"}'
  '{"event":"three"}'
  '{ "source": "hmac-valid" }'
  '{"source":"header-valid"}'
)

# Bodies of rejected requests that must not be present.
REJECTED=(
  '{"source":"hmac-invalid"}'
  '{"source":"hmac-unsigned"}'
  '{"source":"header-wrong"}'
  '{"source":"header-missing"}'
)

for attempt in $(seq 1 24); do
  POD=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$POD" ]; then
    echo "Attempt $attempt: no collector pod found yet, retrying in 5s..."
    sleep 5
    continue
  fi

  LOGS=$(kubectl -n "$NAMESPACE" logs "$POD" --tail=-1)

  # Rejected requests must never produce a log record.
  for body in "${REJECTED[@]}"; do
    if echo "$LOGS" | grep -q -F -- "Body: Str($body)"; then
      echo "The body $body of a rejected request reached the collector pipeline."
      exit 1
    fi
  done

  all_found=true
  for body in "${EXPECTED[@]}"; do
    count=$(echo "$LOGS" | grep -c -F -- "Body: Str($body)")
    if [ "$count" -ne 1 ]; then
      all_found=false
      echo "Attempt $attempt: body $body found $count time(s), expected 1"
    fi
  done

  if $all_found; then
    echo "All accepted events were received exactly once and no rejected event reached the pipeline."
    exit 0
  fi

  sleep 5
done

echo "Timed out waiting for the webhook events."
exit 1
