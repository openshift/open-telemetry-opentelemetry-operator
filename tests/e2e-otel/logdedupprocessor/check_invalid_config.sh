#!/bin/bash
# This script checks that a collector whose log_dedup processor sets both include_fields and
# exclude_fields refuses to start and reports the reason.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector,app.kubernetes.io/instance=${NAMESPACE}.logdedup-invalid"
EXPECTED_ERROR="cannot define both exclude_fields and include_fields"

# The collector container has no readiness probe, so it reports ready for the moment between
# its start and the exit on the invalid configuration. Only a container that stays ready for
# 30 seconds without logging the error counts as a collector that started.
ready_checks=0
last_pod=""
for attempt in $(seq 1 24); do
  POD=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ "$POD" != "$last_pod" ]; then
    ready_checks=0
    last_pod="$POD"
  fi
  if [ -n "$POD" ]; then
    # the error is in the log of the current container or, after a restart, of the previous one
    if { kubectl -n "$NAMESPACE" logs "$POD" 2>/dev/null; kubectl -n "$NAMESPACE" logs "$POD" --previous 2>/dev/null; } | grep -q -- "$EXPECTED_ERROR"; then
      echo "The collector rejected the configuration: \"$EXPECTED_ERROR\""
      exit 0
    fi
    READY=$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    if [ "$READY" = "true" ]; then
      ready_checks=$((ready_checks + 1))
      if [ "$ready_checks" -ge 6 ]; then
        echo "The collector with an invalid log_dedup configuration is ready, but it must not start."
        exit 1
      fi
    else
      ready_checks=0
    fi
  fi
  echo "Attempt $attempt: waiting for the collector to report the configuration error, retrying in 5s..."
  sleep 5
done

echo "Timed out waiting for the configuration error \"$EXPECTED_ERROR\"."
exit 1
