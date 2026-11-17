# OpenTelemetry zPages Extension Test

This test demonstrates the OpenTelemetry zPages extension configuration for exposing live in-process debugging pages.

## 🎯 What This Test Does

The test validates that the zPages extension can:
- Start an HTTP server on the collector exposing `/debug/*` diagnostic pages
- Serve the `servicez` page with build and runtime information
- Serve the `pipelinez` page listing the configured pipelines and their components
- Serve the `extensionz` page listing the configured extensions

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `zpages` extension enabled
- **Key Features**:
  - `endpoint: 0.0.0.0:55679` binds zpages to all interfaces (it defaults to `localhost` only, which isn't reachable from outside the collector pod)
  - `spec.ports` explicitly exposes port `55679` on the collector Service, since the operator has no built-in port mapping for this extension
  - Debug exporter with detailed verbosity so a traces pipeline exists for `pipelinez` to report - the `servicez`/`pipelinez`/`extensionz` pages report static, config-time state, so no telemetry actually needs to flow through that pipeline

### 2. zPages Query Job
- **File**: [`check-zpages.yaml`](./check-zpages.yaml)
- **Contains**: Job that curls the `servicez`, `pipelinez` and `extensionz` debug endpoints from inside the cluster (the zpages Service is only reachable in-cluster)

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the curl Job's output contains the expected content from each zpages endpoint

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Query zPages Endpoints** - Run job from [`check-zpages.yaml`](./check-zpages.yaml)
3. **Check zPages Responses** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the curl Job's logs contain:
- `Service otelcol-contrib` - from the `servicez` page's build info table
- `traces` - the configured pipeline name, from the `pipelinez` page
- `zpages` - the configured extension name, from the `extensionz` page

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- The `/debug/tracez` page is only registered when the collector's tracer provider supports span-processor registration; it is not guaranteed to be available, so this test relies on the always-registered `servicez`/`pipelinez`/`extensionz` pages instead
- The zpages extension has no dedicated operator port-mapping logic, so `spec.ports` must declare the port explicitly or the Service will not expose it
- No telemetry generation step is needed (unlike most other tests in this suite) - `servicez`/`pipelinez`/`extensionz` reflect the collector's static configuration, not live traffic
