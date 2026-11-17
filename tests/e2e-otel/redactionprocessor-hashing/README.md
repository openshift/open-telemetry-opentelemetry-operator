# OpenTelemetry Redaction Processor Hashing and Pattern Test

This test extends the [`redactionprocessor`](../redactionprocessor/) test to the remaining commonly used settings of the Redaction processor.

## 🎯 What This Test Does

The test validates that the Redaction processor can:
- Replace a value that matches `blocked_values` with its SHA3-256 hash (`hash_function: sha3`) instead of `****`
- Hash the value of an allowed key whose name matches `blocked_key_patterns`
- Keep a value that matches `allowed_values`, which takes precedence over `blocked_values`
- Pass attributes in `ignored_keys` and `ignored_key_patterns` through untouched, even when the value looks sensitive
- Sanitize URLs in the attributes listed in `url_sanitizer.attributes`
- Report only counts, not key names, with `summary: info`

## 📋 Test Resources

- [`otel-collector.yaml`](./otel-collector.yaml): OpenTelemetryCollector with the `redaction` processor and the debug exporter
- [`generate-telemetry-data.yaml`](./generate-telemetry-data.yaml): Job that sends one trace with these attributes:
  - `user.email="bob@other.com"`: allowed key, blocked value → hashed
  - `auth.token="abc123"`: allowed key matching `blocked_key_patterns` → hashed
  - `contact.email="alice@mycompany.com"`: matches `allowed_values` → kept
  - `db.svc="cart"`: allowed key, safe value → kept
  - `safe_attribute="4111111111111111"` and `safe_x="keep me"`: ignored by `ignored_keys` and `ignored_key_patterns` → kept; each attribute is matched by only one of the two settings
  - `secret_field="topsecret"`: not allowed → dropped
  - `http.url="https://example.com/users/<uuid>/orders/12345"`: sanitized
- [`check_logs.sh`](./check_logs.sh): Checks the collector debug output, with retries

## 🚀 Test Steps

1. Create the collector
2. Run the Job that sends the trace
3. Wait for the data to be collected
4. Run `check_logs.sh`

## 📝 Key Configuration Notes

- Despite its name, `hash_function: sha3` produces SHA3-256 digests. The expected values in `check_logs.sh` are SHA3-256 of `bob@other.com` and `abc123`; recompute with `openssl dgst -sha3-256`.
- `summary: info` adds only the `redaction.*.count` attributes. The test checks that these are present, but not their exact values, because the counts include attributes that telemetrygen adds itself. `summary: debug` also adds the key names, as in the `redactionprocessor` test.
- The URL sanitizer replaces the variable parts of the URL with `*`, so `https://example.com/users/<uuid>/orders/12345` becomes `*//example.com/users/*/orders/*`.
