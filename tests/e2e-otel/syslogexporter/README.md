# OpenTelemetry Syslog Exporter Test

This test validates the `syslog` exporter (Technology Preview) against a syslog sink running in the test namespace.

## 🎯 What This Test Does

The test validates that the syslog exporter can:
- Send RFC 5424 messages over TCP
- Send RFC 3164 messages over UDP
- Frame RFC 5424 messages with octet counting (RFC 6587)
- Use TLS by default for `tcp`: an exporter without `tls` settings starts a TLS handshake and never sends plain text

## 📋 Test Resources

### 1. Syslog Sink
- **File**: [`syslog-sink.yaml`](./syslog-sink.yaml)
- **Contains**: A small Python sink (ConfigMap, Deployment and Service). It prints every received line prefixed with the listener name, so the raw frames can be checked exactly. Port 5143 does not print data: it reports whether the client starts a TLS handshake.
- **Image**: `registry.access.redhat.com/ubi9/python-311`, which does not need a pull secret.

### 2. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Key Features**:
  - The syslog exporter does not use the log body. The `transform` processor copies it to the `message` attribute and sets `appname` and `hostname`.
  - `endpoint` is the host name only; the port is a separate `port` option.
  - Four exporters: `syslog/tcp` (RFC 5424), `syslog/udp` (RFC 3164), `syslog/octet` (octet counting) and `syslog/tlsdefault` (no `tls` settings)
  - `tls.insecure: true` is needed for plain text `tcp`
  - A `sending_queue` on every exporter, so the failing default-TLS exporter cannot block the others

### 3. Telemetry Data Generator
- **File**: [`generate-logs.yaml`](./generate-logs.yaml)
- **Contains**: A telemetrygen job that sends 3 logs with the body `hello syslog`. The body must not be quoted, because telemetrygen keeps the quote characters.

### 4. Verification Script
- **File**: [`check_syslog.sh`](./check_syslog.sh)
- **Verification Criteria**:
  - 3 RFC 5424 messages on the TCP listener, in the form `<165>1 <timestamp> e2e-host otel-e2e - - - hello syslog`
  - 3 RFC 3164 messages on the UDP listener, in the form `<165>Sep 21 05:36:01 e2e-host otel-e2e: hello syslog`
  - 3 octet counted messages whose length prefix equals the byte length of the message including the final newline
  - The default-TLS port received a TLS handshake and no plain text

## 🚀 Test Steps

1. **Create the sink** - [`syslog-sink.yaml`](./syslog-sink.yaml)
2. **Create OTEL Collector** - [`otel-collector.yaml`](./otel-collector.yaml)
3. **Generate logs** - [`generate-logs.yaml`](./generate-logs.yaml)
4. **Check the received messages** - [`check_syslog.sh`](./check_syslog.sh), which retries until the messages arrive

## 📝 Notes

- `priority` is a raw attribute and defaults to 165; it is not derived from the log severity.
- The sink writes lines under a lock. Unlocked writes from several connections interleave and make messages look lost.
- Attribute values with line breaks are covered by the separate, currently skipped test [`../syslogexporter-frame-injection`](../syslogexporter-frame-injection), see upstream issue open-telemetry/opentelemetry-collector-contrib#49234.
