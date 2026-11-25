#!/bin/bash
# Verifies Intermediate TLS profile injection in the generated TA ConfigMap.
# The operator populates the TA https block with min_version, cipher_suites,
# and curve_preferences from the cluster TLS profile when TA mTLS is enabled.
# curve_preferences uses numeric IANA supported-group IDs because
# component-base's TLSCurvePreferences parser accepts only that form.
# Intermediate profile groups: X25519MLKEM768=4588, X25519=29, P256=23, P384=24.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

# Get the TA ConfigMap.
CM_NAME=$(kubectl get configmap -n "$NAMESPACE" \
  -l app.kubernetes.io/component=opentelemetry-targetallocator \
  -o jsonpath='{.items[0].metadata.name}')
[ -n "$CM_NAME" ] || fail "TA ConfigMap not found"

# Extract the targetallocator.yaml and convert to JSON.
CONFIG=$(kubectl get configmap "$CM_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.targetallocator\.yaml}' | yq -o json)

# Verify https block exists.
HTTPS_ENABLED=$(echo "$CONFIG" | jq -r '.https.enabled // empty')
[ "$HTTPS_ENABLED" = "true" ] || fail "https.enabled: expected 'true', got '$HTTPS_ENABLED'"

# Verify min_version uses component-base format.
MIN_VER=$(echo "$CONFIG" | jq -r '.https.min_version // empty')
[ "$MIN_VER" = "VersionTLS12" ] || fail "https.min_version: expected 'VersionTLS12', got '$MIN_VER'"

# Verify cipher_suites are present (Intermediate profile has TLS 1.2 ciphers).
CIPHERS=$(echo "$CONFIG" | jq '.https.cipher_suites')
[ "$CIPHERS" != "null" ] && [ "$CIPHERS" != "[]" ] \
  || fail "https.cipher_suites: expected non-empty, got '$CIPHERS'"

# Verify curve_preferences as numeric IANA IDs.
CURVES=$(echo "$CONFIG" | jq -c '.https.curve_preferences')
[ "$CURVES" = "[4588,29,23,24]" ] \
  || fail "https.curve_preferences: expected '[4588,29,23,24]', got '$CURVES'"

echo "PASS: Intermediate profile verified on TA ConfigMap"
