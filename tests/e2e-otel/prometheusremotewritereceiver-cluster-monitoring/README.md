# Export OpenShift Monitoring Metrics to the OTEL Collector with Prometheus Remote Write v2

This test configures the OpenShift in-cluster (platform) and user workload monitoring Prometheus instances to export their metrics to an OpenTelemetry Collector with the **Prometheus Remote Write v2** protocol, the way a customer would do it to forward OpenShift metrics to an OTLP-native third-party backend. The Cluster Monitoring Operator config maps carry the remote write configuration (`messageVersion: V2.0`), and the Collector receives the metrics with the `prometheus_remote_write` receiver.

## 🎯 What This Test Does

The test validates that:
- The Cluster Monitoring Operator accepts `remoteWrite[].messageVersion: V2.0` for `prometheusK8s` and for the user workload monitoring `prometheus`
- Platform metrics (`up`, `node_cpu_seconds_total`, `kube_pod_info`), the firing `Watchdog` alert (`ALERTS`) and a recording rule result (`instance:node_cpu_utilisation:rate1m`), the targeted subset the documentation advises for the Technology Preview, and user workload metrics (from a sample application with a `ServiceMonitor`) arrive at the Collector through the `prometheus_remote_write` receiver
- Both Prometheus instances send samples continuously with zero failed samples
- The metrics can be forwarded through the Collector pipeline (verified on the Prometheus exporter endpoint; a third-party backend would use an OTLP exporter instead)

## 📋 Test Resources

### 1. OpenTelemetry Collector
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Contains**: `OpenTelemetryCollector` with the `prometheus_remote_write` receiver on port 9090 (exposed through `spec.ports`), the `memory_limiter` processor as in the documented configuration, and the Prometheus exporter on port 8889 used for verification

### 2. Sample Application
- **File**: [`sample-app.yaml`](./sample-app.yaml)
- **Contains**: `avalanche` deployment exposing gauges, counters, classic histograms, native histograms and summaries, plus a `ServiceMonitor` scraped by user workload monitoring

### 3. Monitoring Stack Configuration
- **Files**: [`cluster-monitoring-config.yaml`](./cluster-monitoring-config.yaml), [`user-workload-monitoring-config.yaml`](./user-workload-monitoring-config.yaml)
- **Contains**: `enableUserWorkload: true` and a `remoteWrite` entry with `messageVersion: V2.0` towards the Collector service for both Prometheus instances. `writeRelabelConfigs` keeps only a few metrics to keep the test light; without it every metric is exported.
- **Cleanup**: [`backup_monitoring_config.sh`](./backup_monitoring_config.sh) saves both config maps before the test changes them (a read error other than NotFound fails the test; the per-run state file is emptied first and again once the cleanup has restored both config maps, so a config map whose backup did not complete is left untouched and no copy from an earlier run can be applied; a state file left behind by an earlier cleanup that did not complete stops the next backup until the cleanup script is run again by hand), [`apply_monitoring_config.sh`](./apply_monitoring_config.sh) applies the test configuration with `oc` so that chainsaw does not delete the shared config maps itself, and [`cleanup_monitoring_config.sh`](./cleanup_monitoring_config.sh), attached to the configuration step as a `cleanup` hook, restores the saved config maps (or deletes the ones that did not exist before) and removes the cluster role binding subject of the verification service account (a binding that does not exist or no longer holds the subject is fine; any other error reading the binding fails the cleanup).

### 4. Verification
- **File**: [`check-metrics.yaml`](./check-metrics.yaml): Job (restricted security context, read-only root filesystem with an `emptyDir` for `/tmp`) that fetches the Collector's Prometheus exporter endpoint and checks that platform metrics from both platform replicas (`prometheus_replica="prometheus-k8s-0"` and `-1`) and user workload metrics from both user workload replicas (`prometheus_replica="prometheus-user-workload-0"` and `-1`) are present
- **File**: [`check_remote_write.sh`](./check_remote_write.sh): queries Thanos Querier for `prometheus_remote_storage_samples_total` (throughput > 0) and `prometheus_remote_storage_samples_failed_total` (must be 0; `_dropped_total` counts the samples removed by `writeRelabelConfigs`) of both Prometheus instances
- **File**: [`check_ocp_version.sh`](./check_ocp_version.sh): fails early on clusters older than OpenShift 5.0

## 🚀 Test Steps

1. **Version check**: `messageVersion` in the Cluster Monitoring Operator config requires OpenShift 5.0 or later
2. **Deploy the Collector** with the `prometheus_remote_write` receiver
3. **Deploy the sample application** and its `ServiceMonitor`
4. **Configure remote write v2** in `cluster-monitoring-config` and `user-workload-monitoring-config`, wait for the user workload monitoring stack
5. **Verify** the metrics on the Collector and the remote write health on the Prometheus side; the monitoring config maps are restored by the `cleanup` hook of the configuration step when the test ends

## 🔍 Key Configuration Notes

- The test is `concurrent: false` and uses a fixed namespace, because it mutates the shared monitoring config maps and the remote write URL points at the Collector service in that namespace.
- Only remote write **v2** is accepted by the receiver (`io.prometheus.write.v2.Request`); the Cluster Monitoring Operator exposes it as `messageVersion: V2.0` since OpenShift 5.0. Run the test with `SKIP_TESTS` on older clusters.
- Each Prometheus instance runs two replicas, so every sample arrives twice, distinguished by the `prometheus_replica` label. A backend has to deduplicate or the user has to filter one replica.
- The Cluster Monitoring Operator does not yet expose the `metadata-wal-records` feature flag or native histogram scraping (MON-4412). Until it does, metrics arrive without type metadata (counters, histogram buckets and summary quantiles become untyped gauges) and classic histograms are not converted to native histograms.

## 🔗 Related Components

- [`prometheusremotewritereceiver`](../prometheusremotewritereceiver/): Collector-to-Collector remote write v2 without the monitoring stack
- [`prometheusremotewriteexporter`](../prometheusremotewriteexporter/): the sending side of the protocol
