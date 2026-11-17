#!/bin/bash
# This script checks that a log body with a line break reaches the syslog sink as ONE message.
# A log body of "first line\n<4>1 ... forged message" must not create a second, forged message.

SINK_SELECTOR="app=syslog-sink"

for attempt in $(seq 1 24); do
  SINK_POD=$(kubectl -n "$NAMESPACE" get pods -l "$SINK_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$SINK_POD" ]; then
    SINK_LOGS=$(kubectl -n "$NAMESPACE" logs "$SINK_POD" --tail=-1)
    received=$(echo "$SINK_LOGS" | grep -c -E "^TCP-5424 <165>1 ")
    forged=$(echo "$SINK_LOGS" | grep -c -E "^TCP-5424 <4>1 ")
    echo "Attempt $attempt: messages=$received forged-messages=$forged"

    if [ "$forged" -gt 0 ]; then
      echo "The line break in the log body created a forged syslog message."
      exit 1
    fi
    if [ "$received" -eq 1 ]; then
      echo "The log with a line break was delivered as a single syslog message."
      exit 0
    fi
  fi
  sleep 5
done

echo "Timed out waiting for the syslog message."
exit 1
