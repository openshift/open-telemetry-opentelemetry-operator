# OpenTelemetry Webhook Event Receiver Test

This test validates the `webhook_event` receiver (Technology Preview): it accepts webhook events over HTTP, optionally authenticates them, and turns them into log records.

## 🎯 What This Test Does

The test validates that the webhook event receiver can:
- Answer the health check on `health_path`
- Split an NDJSON body into one log record per line (`split_logs_at_newline`)
- Verify an HMAC signature (`hmac_signature`, GitHub style `X-Hub-Signature-256: sha256=<hex>`) and reject invalid or missing signatures with 401
- Require a header with an exact value (`required_header`) and reject wrong or missing values with 401
- Be exposed by the operator through a Service port for each receiver endpoint

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Key Features**:
  - Three receiver instances of the same type: `webhook_event/plain` (8088), `webhook_event/hmac` (8089) and `webhook_event/header` (8090)
  - `endpoint` is required and has no default; `path` and `health_path` must start with `/`
  - `required_header` is a plain header equality check. It is not a signature check, use `hmac_signature` for that.
  - Debug exporter with detailed verbosity for verification

### 2. Webhook Client
- **File**: [`send-events.yaml`](./send-events.yaml)
- **Contains**: A Job running a small Python client (ConfigMap). It sends the requests and exits with an error if any status differs from the expected one: health check 200, NDJSON 200, valid HMAC 200, invalid and missing HMAC 401, matching header 200, wrong and missing header 401.
- **Image**: `registry.access.redhat.com/ubi9/python-311`, which does not need a pull secret.

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Verification Criteria**:
  - The three NDJSON lines, the correctly signed event and the event with the right header each appear exactly once
  - The bodies of all rejected requests never appear

## 🚀 Test Steps

1. **Create OTEL Collector** - [`otel-collector.yaml`](./otel-collector.yaml), and check the Service ports 8088, 8089 and 8090
2. **Send events** - [`send-events.yaml`](./send-events.yaml)
3. **Check the received events** - [`check_logs.sh`](./check_logs.sh)

## 🧪 Additional Tests

- [`../webhookeventreceiver-default-endpoint`](../webhookeventreceiver-default-endpoint): a single `webhook_event` receiver whose Service port the operator's `webhook_event` parser (open-telemetry/opentelemetry-operator#5631, operator 0.161.0 and later) takes from `endpoint`. The receiver has no default port, so `endpoint` must be set; without it the operator webhook rejects the collector (`port should not be empty`).
- Not covered yet: a `path` without a leading `/` should fail config validation cleanly. On collector versions without the fix for open-telemetry/opentelemetry-collector-contrib#50893 the collector panics instead, so a test can only be written once the fix is in the used version.

## 📝 Notes

- The Service ports are asserted with `to_string(port)`: a JMESPath comparison of the integer port with a number literal does not match.
- Port names are `port-<number>` because the receiver names are longer than 15 characters.
