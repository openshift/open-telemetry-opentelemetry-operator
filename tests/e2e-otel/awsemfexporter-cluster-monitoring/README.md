# Export OpenShift Monitoring Metrics to AWS CloudWatch via the OTEL Collector

This test exports the OpenShift in-cluster (platform) and user workload monitoring metrics to **AWS CloudWatch**: the Cluster Monitoring Operator sends them to the OpenTelemetry Collector with **Prometheus Remote Write v2** (`messageVersion: V2.0`), the Collector receives them with the `prometheus_remote_write` receiver and exports them with the **AWS EMF exporter** (`awsemf`). It is the third-party-backend variant of [`prometheusremotewritereceiver-cluster-monitoring`](../prometheusremotewritereceiver-cluster-monitoring/).

## 🎯 What This Test Does

- Configures remote write v2 from the platform (`prometheusK8s`) and user workload (`prometheus`) Prometheus instances to the Collector
- Exports the received metrics to CloudWatch with the AWS EMF exporter, with the resource attributes promoted to dimensions (`service.name` and `service.instance.id` carry the Prometheus `job` and `instance` labels)
- Verifies in CloudWatch (namespace `Tracing-OCP-Monitoring`) that platform metrics (`up` with `service.name=node-exporter`, `kube_pod_info`) and user workload metrics (`avalanche_counter_*` with `service.name=metrics-sample-app`) received data points during this run, and that the EMF log stream was created
- Verifies on the Prometheus side that both instances send samples with zero failed samples

## 📋 Test Resources

| File | Purpose |
|------|---------|
| [`create-aws-creds-secret.sh`](./create-aws-creds-secret.sh) | Creates the `aws-credentials` secret from `CLUSTER_PROFILE_DIR/.awscred`, the `aws-creds` secret in `kube-system`, or the AWS CLI configuration (same lookup as the other AWS tests; the secret is created from stdin so the credentials never appear on a command line) |
| [`otel-collector.yaml`](./otel-collector.yaml) | `OpenTelemetryCollector` `emf` with the `prometheus_remote_write` receiver (port 9090 in `spec.ports`), `memory_limiter`, and the `awsemf` exporter (it has no `sending_queue` or `retry_on_failure` settings of its own) |
| [`sample-app.yaml`](./sample-app.yaml) | `avalanche` with a `ServiceMonitor`, scraped by user workload monitoring |
| [`cluster-monitoring-config.yaml`](./cluster-monitoring-config.yaml), [`user-workload-monitoring-config.yaml`](./user-workload-monitoring-config.yaml) | Remote write v2 towards the Collector; `writeRelabelConfigs` keeps `up`, `node_cpu_seconds_total`, `kube_pod_info` and the `avalanche_*` metrics so the test stays light |
| [`check_cloudwatch_metrics.sh`](./check_cloudwatch_metrics.sh) | `aws cloudwatch get-metric-data` (a `SEARCH` over the `OTelLib` + `service.name` rollups that counts only data points published since the sample application was created, so metrics of an earlier run cannot satisfy the check) and `aws logs describe-log-streams`, then the Thanos Querier checks on `prometheus_remote_storage_*` |
| [`backup_monitoring_config.sh`](./backup_monitoring_config.sh), [`apply_monitoring_config.sh`](./apply_monitoring_config.sh), [`cleanup_monitoring_config.sh`](./cleanup_monitoring_config.sh), [`delete_log_group.sh`](./delete_log_group.sh) | The config maps are saved before the test changes them (a per-run state file records saved/absent; without an entry the cleanup leaves the config map untouched, and the state is kept when a restore fails so that the cleanup script can be run again by hand), applied with `oc` (so chainsaw does not delete them itself), and restored by the `cleanup` hook of the configuration step when the test ends (a config map that did not exist before is deleted); the same hook removes the cluster role binding subject (an error reading the binding other than NotFound fails the cleanup) and the CloudWatch log group |
| [`check_ocp_version.sh`](./check_ocp_version.sh) | Fails early on clusters older than OpenShift 5.0 |

## 🔍 Key Configuration Notes

- Requires OpenShift 5.0 or later (`messageVersion` in the Cluster Monitoring Operator config) and AWS credentials; the test is `concurrent: false` and uses a fixed namespace because the remote write URL points at the Collector service in it.
- The AWS EMF exporter turns every label into a CloudWatch dimension. The verification searches the `OTelLib` + `service.name` rollups that `ZeroAndSingleDimensionRollup` creates (`"service.name"="node-exporter"`), where `service.name` is derived from the Prometheus `job` label by the receiver.
- Until the monitoring stack exposes the `metadata-wal-records` feature and native histogram scraping (MON-4412), the metrics arrive untyped: counters are exported as gauge values and classic histograms as their `_bucket`/`_sum`/`_count` series.
- Every sample arrives twice (two Prometheus replicas, `prometheus_replica` dimension).

## 🔗 Related Tests

- [`prometheusremotewritereceiver-cluster-monitoring`](../prometheusremotewritereceiver-cluster-monitoring/): the same flow verified on the Collector's Prometheus exporter, without AWS
- [`awscloudwatchlogsexporter`](../awscloudwatchlogsexporter/): the AWS EMF and CloudWatch Logs exporters with OTLP input
