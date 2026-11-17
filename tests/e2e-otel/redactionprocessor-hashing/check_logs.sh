#!/bin/bash
# This script checks the OpenTelemetry collector pod for evidence that the
# redaction processor hashed blocked values (hash_function: sha3), skipped
# ignored keys, honoured allowed_values over blocked_values, sanitized the
# URL attribute and reported only counts (summary: info).

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector"
NAMESPACE=$NAMESPACE

# sha3 in the redaction processor is SHA3-256. The expected digests are
# SHA3-256("bob@other.com") and SHA3-256("abc123").
SEARCH_STRINGS=(
  "user.email: Str(7fe0a325156a4d8d80739b833f028a6810e90935ba11515c657bdfbce4da1494)"
  "auth.token: Str(f58fa3df820114f56e1544354379820cff464c9c41cb3ca0ad0b0843c9bb67ee)"
  "contact.email: Str(alice@mycompany.com)"
  "db.svc: Str(cart)"
  "safe_attribute: Str(4111111111111111)"
  "safe_x: Str(keep me)"
  "http.url: Str(*//example.com/users/*/orders/*)"
  "redaction.masked.count: Int("
  "redaction.ignored.count: Int("
)

# Raw values, the disallowed attribute and key names in the summary must
# not show up: summary is "info", so only counts are reported.
ERROR_SEARCH_STRINGS=(
  "user.email: Str(bob@other.com)"
  "auth.token: Str(abc123)"
  "secret_field:"
  "topsecret"
  "redaction.masked.keys"
  "redaction.redacted.keys"
  "redaction.allowed.keys"
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
