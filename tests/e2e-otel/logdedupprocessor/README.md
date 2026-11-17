# OpenTelemetry Log Deduplication Processor Test

This test validates the `log_dedup` processor (Technology Preview): identical logs collected within an interval are emitted as a single log with a `log_count` attribute.

## 🎯 What This Test Does

The test validates that the log deduplication processor can:
- Aggregate identical logs into a single record with a `log_count` attribute
- Keep tenants apart with `metadata_keys` (client request metadata, here the `x-scope-orgid` header)
- Add the `first_observed_timestamp` and `last_observed_timestamp` attributes to the emitted logs
- Pass logs that do not match `conditions` through unchanged
- Reject a configuration that sets both `include_fields` and `exclude_fields`

## 📋 Test Resources

### 1. OpenTelemetry Collector Configuration
- **File**: [`otel-collector.yaml`](./otel-collector.yaml)
- **Key Features**:
  - OTLP HTTP receiver with `include_metadata: true`. `metadata_keys` are client metadata (request headers), not resource attributes, so the receiver has to keep them.
  - `log_dedup` with a 10s `interval`, `metadata_keys: [x-scope-orgid]`, `metadata_cardinality_limit` and a `conditions` entry
  - Debug exporter with detailed verbosity for verification

### 2. Telemetry Data Generator
- **File**: [`generate-logs.yaml`](./generate-logs.yaml)
- **Contains**: Two telemetrygen jobs
  - `logs-tenants` is one pod with two containers, `tenant-a` and `tenant-b`. Each sends the same log 5 times with its own `x-scope-orgid` header. The containers start together, so both tenants normally fall into the same `interval`; a processor that ignored `metadata_keys` would then merge them into one record. There is no start barrier (the telemetrygen image has no shell), so a boundary between the two bursts is possible but rare; it can hide such a regression, but it cannot make a correct processor fail.
  - `logs-passthrough` sends 3 logs that do not match the processor condition
- **Workload settings**: the jobs disable the service account token, run as non-root with all capabilities dropped, a read-only root filesystem and `backoffLimit: 0` (a retry would send the logs twice and change the counts)

### 3. Verification Scripts
- [`check_logs.sh`](./check_logs.sh) reads the debug exporter output record by record and checks that
  - the `log_count` values of the deduplicated logs add up to 10, no record counts more than 5 (the tenants were not merged) and there are at least 2 records
  - every deduplicated record has `log_count`, `first_observed_timestamp` and `last_observed_timestamp`
  - the 3 passthrough logs appear individually and have none of these three attributes
- [`chainsaw-test.yaml`](./chainsaw-test.yaml) applies [`otel-collector-invalid.yaml`](./otel-collector-invalid.yaml), and [`check_invalid_config.sh`](./check_invalid_config.sh) checks that the collector reports `cannot define both exclude_fields and include_fields`

### 4. Chainsaw Test Definition
- **File**: [`chainsaw-test.yaml`](./chainsaw-test.yaml)

## 🚀 Test Steps

1. **Create OTEL Collector** - deploy [`otel-collector.yaml`](./otel-collector.yaml)
2. **Generate logs** - run the jobs from [`generate-logs.yaml`](./generate-logs.yaml)
3. **Check the deduplicated logs** - run [`check_logs.sh`](./check_logs.sh), which retries until the 10s interval has elapsed
4. **Check the invalid configuration** - run [`check_invalid_config.sh`](./check_invalid_config.sh)

## 📝 Notes

- The sum of `log_count` is checked instead of an exact number of records, because a burst of logs can be split by an interval boundary.
- The `--body` values of telemetrygen must not be quoted: quote characters become part of the body and the `conditions` expression would not match.
- Deduplication keys include the resource and scope attributes, the log attributes, body and severity. Fields that change on every log (for example timestamps in the body) prevent deduplication unless they are removed with `exclude_fields`.
