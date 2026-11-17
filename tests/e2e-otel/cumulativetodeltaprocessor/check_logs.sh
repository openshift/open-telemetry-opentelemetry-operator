#!/bin/bash
# This script checks the OpenTelemetry collector pod for evidence that the
# cumulative to delta processor converted a cumulative sum metric to delta.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=$NAMESPACE

SEARCH_STRINGS=(
  "Name: cdt_test_metric"
  "DataType: Sum"
  "AggregationTemporality: Delta"
)

# This must NOT appear - it would mean the metric was forwarded unconverted.
ERROR_SEARCH_STRINGS=(
  "AggregationTemporality: Cumulative"
)

for attempt in $(seq 1 30); do
    PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

    if [ ${#PODS[@]} -eq 0 ]; then
        echo "Attempt $attempt: no pods found with label $LABEL_SELECTOR in namespace $NAMESPACE, retrying in 10s..."
        sleep 10
        continue
    fi

    POD=${PODS[0]}
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=-1)

    for ERROR_STRING in "${ERROR_SEARCH_STRINGS[@]}"; do
        if echo "$LOGS" | grep -qF -- "$ERROR_STRING"; then
            echo "\"$ERROR_STRING\" found in $POD. Exiting with error."
            exit 1
        fi
    done

    ALL_FOUND=true
    for STRING in "${SEARCH_STRINGS[@]}"; do
        if ! echo "$LOGS" | grep -qF -- "$STRING"; then
            ALL_FOUND=false
            break
        fi
    done

    if $ALL_FOUND; then
        for STRING in "${SEARCH_STRINGS[@]}"; do
            echo "\"$STRING\" found in $POD"
        done
        echo "Log search completed for all defined strings in pod $POD."
        exit 0
    fi

    if (( attempt < 30 )); then
        echo "Attempt $attempt: not all defined strings found yet in pod $POD, retrying in 10s..."
        sleep 10
    fi
done

echo "Timed out waiting for all defined strings in pod $POD"
exit 1
