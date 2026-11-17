#!/bin/bash
# This script checks the check-pprof Job pod for the pprof HTTP content
# served by the collector's pprof extension.

LABEL_SELECTOR="app=check-pprof"
NAMESPACE=$NAMESPACE

SEARCH_STRINGS=(
  "=== pprof index ==="
  "Types of profiles available"
  "=== goroutine profile ==="
  "goroutine profile: total"
)

# The check-pprof Job has backoffLimit set, so a transient early failure
# (e.g. curl racing the collector's readiness) can leave more than one pod
# under this label - only look at the one that actually succeeded.
PODS=($(kubectl -n $NAMESPACE get pods -l $LABEL_SELECTOR --field-selector=status.phase=Succeeded -o jsonpath='{.items[*].metadata.name}'))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "No succeeded pods found with label $LABEL_SELECTOR in namespace $NAMESPACE"
    exit 1
fi

POD=${PODS[0]}
LOGS=$(kubectl -n $NAMESPACE logs $POD --tail=-1)

for STRING in "${SEARCH_STRINGS[@]}"; do
    if echo "$LOGS" | grep -qF -- "$STRING"; then
        echo "\"$STRING\" found in $POD"
    else
        echo "\"$STRING\" not found in $POD"
        exit 1
    fi
done

echo "Log search completed for all defined strings in pod $POD."
