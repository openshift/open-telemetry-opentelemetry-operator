# OpenTelemetry Headers Setter Extension Value Sources Test

This test extends the [`headerssetterextension`](../headerssetterextension/) test to the other ways `headers_setter` can get a header value.

## 🎯 What This Test Does

The test validates that the headers_setter extension can set outbound OTLP headers from four value sources:
- `from_context`: copies a header of the inbound request
- `value`: a static string
- `from_context` with `default_value`: the default is used when the inbound request has no such header
- `value_file`: the content of a file, here a mounted ConfigMap

## 📋 Test Resources

- [`otel-collector-b.yaml`](./otel-collector-b.yaml): downstream collector. Its `attributes` processor copies the four received headers into `header.*` span attributes so that the debug exporter shows them
- [`hse-token-configmap.yaml`](./hse-token-configmap.yaml): ConfigMap whose `token` key is mounted into collector A at `/etc/hse/token`
- [`otel-collector-a.yaml`](./otel-collector-a.yaml): collector with the `headers_setter` extension, forwarding to collector B
- [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml): Job that sends traces to collector A with `x-scope-orgid: tenant-a`
- [`check_logs.sh`](./check_logs.sh): checks collector B's debug output

## 🚀 Test Steps

1. Create collector B
2. Create the ConfigMap, then collector A
3. Run the Job that sends traces to collector A
4. Wait for the data to be collected
5. Run `check_logs.sh`

## 🔍 Verification

`check_logs.sh` confirms collector B's logs contain:
- `header.scope_orgid: Str(tenant-a)`
- `header.static: Str(static-value)`
- `header.fallback: Str(fallback-value)`
- `header.from_file: Str(file-secret)`

## 📝 Key Configuration Notes

- `include_metadata: true` is required on the receivers of both collectors so that the headers are available as request metadata
- gRPC metadata keys are lower-case, so the header names in this test are lower-case
- Set only one of `value`, `value_file` and `from_context` per header entry; the Collector refuses to start with more than one source
