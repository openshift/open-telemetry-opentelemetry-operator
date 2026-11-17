# OpenTelemetry Redaction Processor Test

This test demonstrates the OpenTelemetry Redaction processor configuration for removing disallowed span attributes and masking sensitive attribute values.

## 🎯 What This Test Does

The test validates that the Redaction processor can:
- Keep only attributes that appear in the `allowed_keys` list, dropping everything else
- Mask an allowed attribute's value with `****` when it matches a `blocked_values` regular expression (a Visa credit card number pattern)
- Leave an allowed attribute untouched when its value matches neither an ignore nor a blocked pattern
- Record which keys were masked and redacted via the `redaction.masked.keys` and `redaction.redacted.keys` summary attributes

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `redaction` processor
- **Key Features**:
  - `allow_all_keys: false` with `allowed_keys: [db.svc, credit_card]` - only these two span attributes survive
  - `blocked_values` masks anything matching a Visa credit card number pattern
  - `summary: debug` adds the `redaction.masked.keys`/`redaction.redacted.keys` diagnostic attributes used for verification
  - Debug exporter with detailed verbosity for verification

### 2. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that generates test traces with:
  - `credit_card="4111111111111111"` - allowed key, blocked value → should be masked
  - `db.svc="cart"` - allowed key, safe value → should pass through unchanged
  - `secret_field="topsecret"` - not in `allowed_keys` → should be dropped entirely

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the masked, dropped and passed-through attributes in the collector's debug output

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Generate Traces** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
3. **Wait for Processing** - Allow time for telemetry data to flow through the pipeline
4. **Check Redacted Attributes** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the collector logs contain:
- `credit_card: Str(****)` - the credit card number masked
- `db.svc: Str(cart)` - the allowed, non-sensitive attribute unchanged
- `redaction.masked.keys: Str(credit_card)` - the summary attribute naming what was masked
- `redaction.redacted.keys: Str(network.peer.address,secret_field,service.peer.name)` - the summary attribute naming what was dropped, including `secret_field`

The script also fails if the raw `4111111111111111` value or the dropped `secret_field: Str(topsecret)` attribute is found, which would mean redaction did not happen.

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Attributes are filtered against `allowed_keys` first; only what survives that filter is then checked against `blocked_values`
- `redaction.redacted.keys` also includes attributes telemetrygen adds automatically (`network.peer.address`, `service.peer.name`) since only `db.svc` and `credit_card` are allowed
- `summary: debug` is intentionally verbose for test verification; production configs may prefer `info` or `silent` to avoid leaking which keys were redacted
