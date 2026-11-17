# OpenTelemetry Span Metrics Connector Test

This test demonstrates the OpenTelemetry Span Metrics connector configuration for deriving Request, Error and Duration (R.E.D) metrics from span data.

## 🎯 What This Test Does

The test validates that the Span Metrics connector can:
- Consume spans from a traces pipeline
- Aggregate `calls` (request count) and `duration` (histogram) metrics keyed by `service.name`, `span.name`, `span.kind` and `status.code`
- Emit those metrics into a metrics pipeline

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `span_metrics` connector bridging a traces pipeline to a metrics pipeline
- **Key Features**:
  - `span_metrics` connector is the exporter of the `traces` pipeline and the receiver of the `metrics` pipeline
  - `metrics_flush_interval: 5s` shortens the default 60s flush interval so the test doesn't have to wait as long
  - Debug exporter with detailed verbosity for verification

### 2. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that generates test traces via telemetrygen

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the derived `calls` and `duration` metrics in the collector's debug output

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Generate Traces** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
3. **Wait for the Metrics Flush** - Allow the connector's flush interval to elapse
4. **Check Derived Metrics** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the collector logs contain:
- `Name: traces.span.metrics.calls` - the request count metric derived from spans
- `Name: traces.span.metrics.duration` - the duration histogram metric derived from spans
- `service.name: Str(spanmetrics-test)` - the metrics carry the originating service name as a data point attribute

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Use the canonical connector name `span_metrics`; the legacy alias `spanmetrics` still works but is deprecated
- The connector only flushes aggregated metrics on its `metrics_flush_interval` (default 60s), so tests should shorten it to keep runtime reasonable
- Each metric carries a `collector.instance.id` dimension by default to satisfy the single-writer principle in multi-deployment setups
