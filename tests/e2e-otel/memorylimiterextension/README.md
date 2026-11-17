# OpenTelemetry Memory Limiter Extension Test

This test demonstrates the OpenTelemetry memory_limiter extension configuration for rejecting incoming telemetry when the collector is over its configured memory limit.

## 🎯 What This Test Does

The test validates that the memory_limiter extension can:
- Run as a `middlewares` entry on the OTLP receiver's gRPC and HTTP protocols
- Detect that memory usage is above its configured limit and force a GC
- Reject (refuse) incoming export requests once usage remains above the soft limit, returning a `RESOURCE_EXHAUSTED` gRPC error to the client

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `memory_limiter` extension wired into the `otlp` receiver as a middleware
- **Key Features**:
  - `limit_mib: 1` is set unrealistically low so the extension trips immediately and deterministically, without needing to generate real memory pressure
  - `check_interval: 1s` keeps the trip time short for the test
  - `receivers.otlp.protocols.grpc/http.middlewares` references the extension by its `id`
  - **This test uses the Red Hat build of OpenTelemetry's own collector image** (`registry.redhat.io/rhosdt/opentelemetry-collector-rhel9:latest`) instead of the public `ghcr.io/open-telemetry/...otelcol-contrib` image used elsewhere in `e2e-otel/` - the `memorylimiterextension` component is not built into the public upstream contrib distribution (see also [`tests/e2e-otel/journaldreceiver`](../journaldreceiver) for the same pattern)

### 2. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that attempts to send a trace via telemetrygen with `--allow-export-failures`, so the job still exits `0` even though the collector is expected to reject the export

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates both sides of the rejection - the collector's own log messages, and the `RESOURCE_EXHAUSTED` error observed by the telemetrygen client

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml) with a 1 MiB memory limit
2. **Wait for the Limiter to Trip** - Give the `check_interval` time to detect the over-limit condition
3. **Attempt to Send Traces** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
4. **Check the Rejection** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms:
- The collector logs contain `Memory limiter configured`, `Memory usage is above hard limit. Forcing a GC.` and `Memory usage is above soft limit. Refusing data.`
- The telemetrygen job's logs contain `code = ResourceExhausted desc = RESOURCE_EXHAUSTED`, confirming the client's export was actually refused at the receiver

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- `memory_limiter` replaces the older `memorylimiterprocessor` pattern - as a receiver middleware it can reject requests before they're even converted to OTLP, rather than dropping data further down the pipeline
- Once memory usage drops back within limits, the extension logs `Memory usage back within limits. Resuming normal operation.` and resumes accepting data - this test only exercises the tripped state
