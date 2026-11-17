# OpenTelemetry pprof Extension Test

This test demonstrates the OpenTelemetry pprof extension configuration for exposing Go's `net/http/pprof` profiling endpoints on the collector.

## 🎯 What This Test Does

The test validates that the pprof extension can:
- Start an HTTP server on the collector exposing `/debug/pprof/*` profiling endpoints
- Serve the pprof index page listing the available profile types
- Serve a live goroutine profile

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: OpenTelemetryCollector with the `pprof` extension enabled
- **Key Features**:
  - `endpoint: 0.0.0.0:1777` binds pprof to all interfaces (it defaults to `localhost` only, which isn't reachable from outside the collector pod)
  - `spec.ports` explicitly exposes port `1777` on the collector Service, since the operator has no built-in port mapping for this extension

### 2. pprof Query Job
- **File**: [`check-pprof.yaml`](./check-pprof.yaml)
- **Contains**: Job that curls the pprof index page and the goroutine profile from inside the cluster (the pprof Service is only reachable in-cluster)

### 3. Verification Script
- **File**: [`check_logs.sh`](./check_logs.sh)
- **Purpose**: Validates the curl Job's output contains the expected pprof content

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)
- **Contains**: Complete test workflow orchestration

## 🚀 Test Steps

1. **Create OTEL Collector** - Deploy from [`otel-collector.yaml`](./otel-collector.yaml)
2. **Query pprof Endpoints** - Run job from [`check-pprof.yaml`](./check-pprof.yaml)
3. **Check pprof Responses** - Execute [`check_logs.sh`](./check_logs.sh) validation script

## 🔍 Verification

[`check_logs.sh`](./check_logs.sh) confirms the curl Job's logs contain:
- `Types of profiles available` - from the pprof index page
- `goroutine profile: total` - from the live goroutine profile endpoint

## 🧹 Cleanup

The test runs in a dynamically created namespace and all resources are cleaned up automatically when the test completes.

## 📝 Key Configuration Notes

- The pprof extension has no dedicated operator port-mapping logic, so `spec.ports` must declare the port explicitly or the Service will not expose it
- Profiling endpoints are always live while the collector is running, so no telemetry generation is required to exercise this extension
