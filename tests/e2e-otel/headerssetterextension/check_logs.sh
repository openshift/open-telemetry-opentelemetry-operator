#!/bin/bash
# This script checks collector B's pod for evidence that the x-scope-orgid
# header, set by collector A's headers_setter extension from the inbound
# request context, was propagated all the way to collector B.

LABEL_SELECTOR="app.kubernetes.io/name=hse-b-collector"
NAMESPACE=$NAMESPACE

SEARCH_STRINGS=(
  "tenant.id: Str(tenant-a)"
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
