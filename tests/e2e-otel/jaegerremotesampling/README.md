# OpenTelemetry Jaeger Remote Sampling Extension Test

This test demonstrates the OpenTelemetry jaegerremotesampling extension configuration for serving Jaeger remote sampling strategies from a local strategies file.

## 🎯 What This Test Does

The test validates that the jaegerremotesampling extension can:
- Load sampling strategies from a file mounted into the collector
- Serve a per-service probabilistic sampling strategy over its HTTP API
- Fall back to the configured default strategy for services with no explicit entry

## 📋 Test Resources

### 1. Sampling Strategies ConfigMap
- **File**: [`sampling-strategies-configmap.yaml`](./sampling-strategies-configmap.yaml)
- **Contains**: A `sampling_strategies.json` file defining a probabilistic strategy (`param: 0.8`) for service `foo` and a default probabilistic strategy (`param: 0.5`) for everything else

### 2. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `jaegerremotesampling` extension enabled
- **Key Features**:
  - `source.file` points at the strategies file mounted from the ConfigMap
  - `http.endpoint: 0.0.0.0:5778` binds the sampling API to all interfaces (it defaults to `localhost` only, which isn't reachable from outside the collector pod)
  - `spec.ports` explicitly exposes port `5778` on the collector Service, since the operator has no built-in port mapping for this extension

### 3. Sampling Query Job
- **File**: [`check-sampling.yaml`](./check-sampling.yaml)
- **Contains**: Job that curls the `/sampling` endpoint for both a known (`foo`) and an unknown service from inside the cluster (the sampling Service is only reachable in-cluster)

### 4. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the curl Job's output contains the expected per-service and default sampling strategy JSON

### 5. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create the Strategies ConfigMap** - Deploy from [`sampling-strategies-configmap.yaml`](./sampling-strategies-configmap.yaml)
2. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
3. **Query the Sampling Endpoint** - Run job from [`check-sampling.yaml`](./check-sampling.yaml)
4. **Check the Returned Strategies** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the curl Job's logs contain:
- `{"probabilisticSampling":{"samplingRate":0.8}}` - the per-service strategy returned for `service=foo`
- `{"probabilisticSampling":{"samplingRate":0.5}}` - the default strategy returned for an unrecognized service

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- The jaegerremotesampling extension has no dedicated operator port-mapping logic, so `spec.ports` must declare the port explicitly or the Service will not expose it
- `source.file` and `source.remote` are mutually exclusive - exactly one source must be configured
- At least one of `http` or `grpc` must be configured; this test only exercises the HTTP API
