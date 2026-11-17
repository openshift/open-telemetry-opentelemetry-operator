#!/bin/bash
# This script checks the syslog messages received by the sink for the four syslog exporters of
# the test.
#
# The collector receives 3 logs with the body "hello syslog". The transform processor copies the
# body to the "message" attribute and sets "appname" and "hostname". Every exporter receives all
# 3 logs:
#   syslog/tcp         RFC 5424 over TCP
#   syslog/udp         RFC 3164 over UDP
#   syslog/octet       RFC 5424 over TCP with octet counting (RFC 6587)
#   syslog/tlsdefault  no tls settings: TLS is on by default, so the sink sees a TLS handshake
#                      and never a plain text syslog message

SINK_SELECTOR="app=syslog-sink"
EXPECTED=3

RFC5424='<165>1 [0-9T:.+Z-]+ e2e-host otel-e2e - - - hello syslog'
RFC3164='<165>[A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} e2e-host otel-e2e: hello syslog'

for attempt in $(seq 1 24); do
  SINK_POD=$(kubectl -n "$NAMESPACE" get pods -l "$SINK_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$SINK_POD" ]; then
    echo "Attempt $attempt: sink pod not found yet, retrying in 5s..."
    sleep 5
    continue
  fi

  SINK_LOGS=$(kubectl -n "$NAMESPACE" logs "$SINK_POD" --tail=-1)

  tcp=$(echo "$SINK_LOGS" | grep -c -E "^TCP-5424 ${RFC5424}\$")
  udp=$(echo "$SINK_LOGS" | grep -c -E "^UDP-3164 ${RFC3164}\$")
  octet=$(echo "$SINK_LOGS" | grep -c -E "^TCP-OCTET [0-9]+ ${RFC5424}\$")
  tlsdefault_plain=$(echo "$SINK_LOGS" | grep -c -E "^TCP-TLSDEFAULT received .* tls-handshake=False")
  tlsdefault_tls=$(echo "$SINK_LOGS" | grep -c -E "^TCP-TLSDEFAULT received .* tls-handshake=True")

  echo "Attempt $attempt: rfc5424/tcp=$tcp rfc3164/udp=$udp octet-counting=$octet tls-default-port: plain-text=$tlsdefault_plain tls-handshakes=$tlsdefault_tls"

  # Plain text on the default TLS port means that TLS is not on by default: this never recovers.
  if [ "$tlsdefault_plain" -gt 0 ]; then
    echo "A plain text syslog message reached the sink through an exporter without tls settings."
    exit 1
  fi

  if [ "$tcp" -eq "$EXPECTED" ] && [ "$udp" -eq "$EXPECTED" ] && [ "$octet" -eq "$EXPECTED" ] && [ "$tlsdefault_tls" -gt 0 ]; then
    # The octet counting prefix has to be the byte length of the record including the final newline.
    bad_length=0
    while IFS= read -r line; do
      record=${line#TCP-OCTET }
      length=${record%% *}
      payload=${record#* }
      if [ "$length" -ne $((${#payload} + 1)) ]; then
        bad_length=$((bad_length + 1))
        echo "Wrong octet count $length for a payload of $((${#payload} + 1)) bytes: $payload"
      fi
    done < <(echo "$SINK_LOGS" | grep -E "^TCP-OCTET ")
    if [ "$bad_length" -gt 0 ]; then
      exit 1
    fi
    echo "All syslog messages have the expected format and TLS is on by default for tcp."
    exit 0
  fi

  sleep 5
done

echo "Timed out waiting for the syslog messages."
echo "--- sink logs ---"
echo "$SINK_LOGS"
exit 1
