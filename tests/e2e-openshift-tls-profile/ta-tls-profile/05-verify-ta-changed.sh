#!/bin/bash
# Verifies changed TLS profile injection in the generated TA ConfigMap.
# Reads expected values from the tls-profile-expected ConfigMap
# (created by 04-patch-profile.sh, reused from the collector test).
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

EXPECTED_MIN=$(oc get configmap tls-profile-expected -n "$NAMESPACE" -o jsonpath='{.data.min_version}')
EXPECTED_CIPHERS=$(oc get configmap tls-profile-expected -n "$NAMESPACE" -o jsonpath='{.data.expect_ciphers}')
EXPECT_CURVES=$(oc get configmap tls-profile-expected -n "$NAMESPACE" -o jsonpath='{.data.expect_curves}')
EXPECTED_CURVES=$(oc get configmap tls-profile-expected -n "$NAMESPACE" -o jsonpath='{.data.expected_curves}')

# Map collector-format min_version to component-base format for TA comparison.
case "$EXPECTED_MIN" in
  "1.0") EXPECTED_CB="VersionTLS10" ;;
  "1.1") EXPECTED_CB="VersionTLS11" ;;
  "1.3") EXPECTED_CB="VersionTLS13" ;;
  *)     EXPECTED_CB="VersionTLS12" ;;
esac
echo "Verifying TA profile: min_version=$EXPECTED_CB, expect_ciphers=$EXPECTED_CIPHERS, expect_curves=$EXPECT_CURVES"

# Get the TA ConfigMap.
CM_NAME=$(kubectl get configmap -n "$NAMESPACE" \
  -l app.kubernetes.io/component=opentelemetry-targetallocator \
  -o jsonpath='{.items[0].metadata.name}')
[ -n "$CM_NAME" ] || fail "TA ConfigMap not found"

CONFIG=$(kubectl get configmap "$CM_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.targetallocator\.yaml}' | yq -o json)

# Verify min_version.
MIN_VER=$(echo "$CONFIG" | jq -r '.https.min_version // empty')
[ "$MIN_VER" = "$EXPECTED_CB" ] \
  || fail "https.min_version: expected '$EXPECTED_CB', got '$MIN_VER'"

# Verify cipher_suites.
CIPHERS=$(echo "$CONFIG" | jq '.https.cipher_suites')
if [ "$EXPECTED_CIPHERS" = "true" ]; then
  [ "$CIPHERS" != "null" ] && [ "$CIPHERS" != "[]" ] \
    || fail "https.cipher_suites: expected non-empty, got '$CIPHERS'"
else
  [ "$CIPHERS" = "null" ] \
    || fail "https.cipher_suites: expected null (TLS 1.3), got '$CIPHERS'"
fi

# Verify curve_preferences as numeric IANA IDs.
CURVES=$(echo "$CONFIG" | jq -c '.https.curve_preferences')
if [ "$EXPECT_CURVES" = "true" ]; then
  # Convert collector-format expected_curves to IANA IDs for comparison.
  # Intermediate/Modern: ["X25519MLKEM768","X25519","P256","P384"] -> [4588,29,23,24]
  EXPECTED_IANA=$(echo "$EXPECTED_CURVES" | jq -c '[.[] |
    if . == "X25519MLKEM768" then 4588
    elif . == "X25519" then 29
    elif . == "P256" then 23
    elif . == "P384" then 24
    elif . == "P521" then 25
    else empty end]')
  [ "$CURVES" = "$EXPECTED_IANA" ] \
    || fail "https.curve_preferences: expected '$EXPECTED_IANA', got '$CURVES'"
else
  [ "$CURVES" = "null" ] \
    || fail "https.curve_preferences: expected null (profile has no groups), got '$CURVES'"
fi

echo "PASS: Changed profile verified on TA ConfigMap (min_version=$EXPECTED_CB)"
