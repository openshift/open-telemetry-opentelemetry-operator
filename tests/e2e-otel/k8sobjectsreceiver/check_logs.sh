#!/bin/bash
# This script checks the OpenTelemetry collector pod for the presence of Logs.

# Define the label selector
LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=chainsaw-k8sobjectsreceiver

# Define the search strings
SEARCH_STRING1='Body: Map({"object":'
SEARCH_STRING2='k8s.resource.name'
SEARCH_STRING3='event.domain'
SEARCH_STRING4='event.name'

SEARCH_STRINGS=("$SEARCH_STRING1" "$SEARCH_STRING2" "$SEARCH_STRING3" "$SEARCH_STRING4")

for attempt in $(seq 1 30); do
  PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))
  ALL_FOUND=true

  for search in "${SEARCH_STRINGS[@]}"; do
    found=false
    for POD in "${PODS[@]}"; do
      if kubectl -n $NAMESPACE --tail=500 logs "$POD" 2>/dev/null | grep -q -- "$search"; then
        found=true
        break
      fi
    done
    if ! $found; then
      ALL_FOUND=false
      break
    fi
  done

  if $ALL_FOUND; then
    echo "Found all the Kubernetes events in OpenTelemetry collector."
    exit 0
  fi

  if (( attempt < 30 )); then
    echo "Attempt $attempt: Not all event log strings found yet, retrying in 10s..."
    sleep 10
  fi
done

echo "No Kubernetes events found in OpenTelemetry collector after 30 attempts"
exit 1
