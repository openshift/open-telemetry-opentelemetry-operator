#!/bin/bash
# This script confirms the memory_limiter extension tripped on the
# collector and rejected an incoming export from the telemetrygen job.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=$NAMESPACE

COLLECTOR_SEARCH_STRINGS=(
  "Memory limiter configured"
  "Memory usage is above hard limit. Forcing a GC."
  "Memory usage is above soft limit. Refusing data."
)

for attempt in $(seq 1 30); do
    PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR -o jsonpath='{.items[*].metadata.name}'))

    if [ ${#PODS[@]} -eq 0 ]; then
        echo "Attempt $attempt: no collector pods found with label $LABEL_SELECTOR in namespace $NAMESPACE, retrying in 10s..."
        sleep 10
        continue
    fi

    POD=${PODS[0]}
    LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=-1)
    ALL_FOUND=true

    for STRING in "${COLLECTOR_SEARCH_STRINGS[@]}"; do
        if ! echo "$LOGS" | grep -qF -- "$STRING"; then
            ALL_FOUND=false
            break
        fi
    done

    if $ALL_FOUND; then
        for STRING in "${COLLECTOR_SEARCH_STRINGS[@]}"; do
            echo "\"$STRING\" found in $POD"
        done
        break
    fi

    if (( attempt < 30 )); then
        echo "Attempt $attempt: not all collector strings found yet in pod $POD, retrying in 10s..."
        sleep 10
    else
        echo "Timed out waiting for all collector strings in pod $POD"
        exit 1
    fi
done

# The telemetrygen Job has already been asserted succeeded by this point, so
# its logs are complete - but a Job that needed a retry can leave more than
# one pod under the same label, so only look at the one that actually
# succeeded.
GEN_PODS=($(kubectl -n $NAMESPACE get pods -l app=traces-memorylimiter --field-selector=status.phase=Succeeded -o jsonpath='{.items[*].metadata.name}'))

if [ ${#GEN_PODS[@]} -eq 0 ]; then
    echo "No succeeded telemetrygen pods found with label app=traces-memorylimiter in namespace $NAMESPACE"
    exit 1
fi

GEN_POD=${GEN_PODS[0]}
GEN_LOGS=$(kubectl -n $NAMESPACE logs $GEN_POD --tail=-1)

if echo "$GEN_LOGS" | grep -qF -- "code = ResourceExhausted desc = RESOURCE_EXHAUSTED"; then
    echo "\"code = ResourceExhausted desc = RESOURCE_EXHAUSTED\" found in $GEN_POD"
else
    echo "\"code = ResourceExhausted desc = RESOURCE_EXHAUSTED\" not found in $GEN_POD"
    exit 1
fi

echo "Log search completed for all defined strings."
