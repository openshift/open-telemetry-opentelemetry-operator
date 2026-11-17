#!/bin/bash
# This script checks the debug exporter output of the OpenTelemetry collector for the
# deduplicated logs of the log_dedup processor.
#
# Two tenants (x-scope-orgid header, configured in metadata_keys) each send the same log 5 times,
# from containers that start together so that both tenants normally fall into the same processor
# interval (see generate-logs.yaml for the rare case where they do not).
# The processor has to keep the tenants apart, so the log_count values of the deduplicated
# records add up to 10 and no single record counts more than 5. Logs that do not match the
# processor condition must pass through unchanged, without a log_count attribute and without the
# first/last observed timestamp attributes.
#
# The debug exporter prints the body of a record before its attributes, so every attribute line is
# attributed to the record whose body was seen last.

LABEL_SELECTOR="app.kubernetes.io/component=opentelemetry-collector,app.kubernetes.io/instance=${NAMESPACE}.logdedup"
EXPECTED_SUM=10
MAX_PER_TENANT=5
EXPECTED_PASSTHROUGH=3

for attempt in $(seq 1 24); do
  POD=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$POD" ]; then
    echo "Attempt $attempt: no collector pod found yet, retrying in 5s..."
    sleep 5
    continue
  fi

  LOGS=$(kubectl -n "$NAMESPACE" logs "$POD" --tail=-1)

  sum=0
  max=0
  dedup_records=0
  dedup_with_count=0
  dedup_with_first=0
  dedup_with_last=0
  passthrough=0
  passthrough_with_extra=0
  kind=""
  while IFS= read -r line; do
    case "$line" in
      *"LogRecord #"*) kind="" ;;
      *"Body: Str(duplicate message)"*)
        kind="dedup"
        dedup_records=$((dedup_records + 1))
        ;;
      *"Body: Str(unique passthrough message)"*)
        kind="passthrough"
        passthrough=$((passthrough + 1))
        ;;
      *"-> log_count: Int("*)
        n=${line##*Int(}
        n=${n%%)*}
        if [ "$kind" = "dedup" ]; then
          sum=$((sum + n))
          dedup_with_count=$((dedup_with_count + 1))
          if [ "$n" -gt "$max" ]; then max=$n; fi
        elif [ "$kind" = "passthrough" ]; then
          passthrough_with_extra=$((passthrough_with_extra + 1))
        fi
        ;;
      *"-> first_observed_timestamp: Str("*)
        if [ "$kind" = "dedup" ]; then
          dedup_with_first=$((dedup_with_first + 1))
        elif [ "$kind" = "passthrough" ]; then
          passthrough_with_extra=$((passthrough_with_extra + 1))
        fi
        ;;
      *"-> last_observed_timestamp: Str("*)
        if [ "$kind" = "dedup" ]; then
          dedup_with_last=$((dedup_with_last + 1))
        elif [ "$kind" = "passthrough" ]; then
          passthrough_with_extra=$((passthrough_with_extra + 1))
        fi
        ;;
    esac
  done <<< "$LOGS"

  echo "Attempt $attempt: deduplicated records=$dedup_records (log_count=$dedup_with_count first_ts=$dedup_with_first last_ts=$dedup_with_last) sum(log_count)=$sum max(log_count)=$max passthrough=$passthrough passthrough_with_dedup_attributes=$passthrough_with_extra"

  # More than expected can never become correct by waiting.
  if [ "$sum" -gt "$EXPECTED_SUM" ] || [ "$max" -gt "$MAX_PER_TENANT" ] || [ "$passthrough_with_extra" -gt 0 ]; then
    echo "Unexpected deduplication result (tenants merged or passthrough logs deduplicated)."
    exit 1
  fi

  if [ "$sum" -eq "$EXPECTED_SUM" ] && [ "$dedup_records" -ge 2 ] && [ "$passthrough" -eq "$EXPECTED_PASSTHROUGH" ]; then
    # Every deduplicated record has to carry all three attributes; all records are already emitted.
    if [ "$dedup_with_count" -ne "$dedup_records" ] || [ "$dedup_with_first" -ne "$dedup_records" ] || [ "$dedup_with_last" -ne "$dedup_records" ]; then
      echo "Not every deduplicated record has the log_count, first_observed_timestamp and last_observed_timestamp attributes."
      exit 1
    fi
    echo "Logs of both tenants were deduplicated separately and non-matching logs passed through unchanged."
    exit 0
  fi

  sleep 5
done

echo "Timed out waiting for the deduplicated logs."
exit 1
