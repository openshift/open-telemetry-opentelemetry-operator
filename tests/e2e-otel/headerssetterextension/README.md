# OpenTelemetry Headers Setter Extension Test

This test demonstrates the OpenTelemetry headers_setter extension configuration for propagating a request header from an inbound request to an outbound OTLP export.

## 🎯 What This Test Does

The test validates that the headers_setter extension can:
- Read a value that arrived on an inbound gRPC request's context (via `include_metadata: true` on the receiver)
- Set that value as a header on the outbound OTLP export of a downstream collector, using it as the exporter's `auth.authenticator`

## 📋 Test Resources

This test deploys two collectors to observe a header propagating end to end:

### 1. Collector B (downstream receiver)
- **File**: [`otel-collector-b.yaml`](./otel-collector-b.yaml)
- **Contains**: OpenTelemetryCollector receiving from collector A
- **Key Features**:
  - `include_metadata: true` puts the incoming `x-scope-orgid` header on the request context
  - An `attributes` processor promotes it into a `tenant.id` span attribute with `from_context: "metadata.x-scope-orgid"`, so it is visible in the debug exporter output

### 2. Collector A (sets the header)
- **File**: [`otel-collector-a.yaml`](./otel-collector-a.yaml)
- **Contains**: OpenTelemetryCollector with the `headers_setter` extension, forwarding to collector B
- **Key Features**:
  - `include_metadata: true` on its own receiver makes the inbound `x-scope-orgid` header available on the context
  - `headers_setter` is configured with `from_context: x-scope-orgid`, re-reading that same header off the context and setting it on the outbound OTLP export
  - The OTLP exporter references the extension via `auth.authenticator: headers_setter`

### 3. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that sends traces to collector A with a custom `x-scope-orgid: tenant-a` OTLP header

### 4. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates collector B's debug output shows the propagated header

### 5. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create Collector B** - Deploy from [`otel-collector-b.yaml`](./otel-collector-b.yaml) so it's ready to receive
2. **Create Collector A** - Deploy from [`otel-collector-a.yaml`](./otel-collector-a.yaml)
3. **Generate Traces** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml), sending a custom header to collector A
4. **Wait for Processing** - Allow time for the trace to flow through both collectors
5. **Check Header Propagation** - Execute [`check_logs.sh`](./check_logs.sh) validation script against collector B

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms collector B's logs contain:
- `tenant.id: Str(tenant-a)` - the value of the `x-scope-orgid` header sent to collector A, round-tripped through `headers_setter` and re-observed on collector B

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- `from_context` on `headers_setter` and on the `attributes` processor's actions read the same underlying per-request client metadata, but with different key syntax: the processor requires a `metadata.` prefix (`metadata.x-scope-orgid`), `headers_setter` does not (`x-scope-orgid`)
- `include_metadata: true` is required on **both** collectors' receivers - collector A needs it to read the inbound header, collector B needs it to read the header collector A re-sent
- gRPC metadata keys are case-insensitive and are read back lower-cased, so this test uses an already-lowercase header name (`x-scope-orgid`) throughout to avoid a mismatch
