# OpenTelemetry Span Processor Test

This test demonstrates the OpenTelemetry Span processor configuration for renaming spans from their attributes and overriding span status.

## 🎯 What This Test Does

The test validates that the Span processor can:
- Rename a span using the `name.from_attributes` setting, concatenating attribute values with a separator
- Override a span's status code and message using the `status` setting

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with a single `span` processor configuring both `name` and `status`
- **Key Features**:
  - `name.from_attributes` renames spans to `<db.svc>::<operation>`
  - `status` sets every span's status to `Error` with a custom description
  - Both transformations are applied to the same span in one pass - they act on independent fields, so a single processor instance and pipeline verify both
  - Debug exporter with detailed verbosity for verification

### 2. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that generates test traces with the `db.svc` and `operation` span attributes used by the rename rule

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the renamed span name and overridden status in the collector's debug output

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Generate Traces** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
3. **Wait for Processing** - Allow time for telemetry data to flow through the pipeline
4. **Check Processed Spans** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the collector logs contain:
- `Name           : cart::checkout` - the span renamed from its `db.svc`/`operation` attributes
- `Status code    : Error` - the status code overridden by the `status` setting
- `Status message : span processor test error status` - the custom status description

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- `name` and `status` are independent settings on the same `span` processor config and are both applied to every span that passes through it
- `name.from_attributes` requires all listed attribute keys to be present on the span, otherwise no rename occurs
- `status.description` is only applied when `status.code` is `Error`
