# OpenTelemetry Cumulative to Delta Processor Test

This test demonstrates the OpenTelemetry Cumulative to Delta processor configuration for converting cumulative monotonic sum metrics to delta aggregation temporality.

## 🎯 What This Test Does

The test validates that the Cumulative to Delta processor can:
- Convert a cumulative, monotonic sum metric to delta aggregation temporality
- Leave the metric's data type and monotonicity unchanged while only the aggregation temporality is rewritten

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `cumulative_to_delta` processor configured to convert `sum` type metrics
- **Key Features**:
  - `include.metric_types: [sum]` selects all monotonic sum metrics for conversion
  - Debug exporter with detailed verbosity for verification

### 2. Telemetry Data Generator
- **File**: [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
- **Contains**: Job that generates a cumulative, monotonic sum metric via telemetrygen (`--metric-type=Sum --aggregation-temporality=cumulative`)

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the metric was converted to delta temporality in the collector's debug output

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Generate a Cumulative Sum Metric** - Run job from [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml)
3. **Wait for Processing** - Allow time for the metric to flow through the pipeline
4. **Check Converted Metric** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the collector logs contain:
- `Name: cdt_test_metric` - the generated metric
- `DataType: Sum` - the metric type is unchanged
- `AggregationTemporality: Delta` - the temporality was converted from cumulative to delta

The script also fails if `AggregationTemporality: Cumulative` is found, which would mean the metric passed through unconverted.

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- Use the canonical processor name `cumulative_to_delta`; the legacy alias `cumulativetodelta` still works but logs a deprecation warning
- Only monotonic sum, histogram, and exponential histogram metrics are converted; non-monotonic sums and metrics already using delta temporality are forwarded unchanged
- The processor is stateful — it tracks the last observed cumulative value per metric identity to compute each delta
