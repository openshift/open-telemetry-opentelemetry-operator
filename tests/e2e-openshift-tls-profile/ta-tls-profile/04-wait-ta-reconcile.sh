#!/bin/bash
# Wait for the operator to restart after the APIServer TLS profile change
# and re-reconcile the TA with the new profile settings.
set -ex

EXPECTED_MIN=$(kubectl get configmap tls-profile-expected -n "$NAMESPACE" \
  -o jsonpath='{.data.min_version}')

# Map collector-format min_version to component-base format for TA comparison.
case "$EXPECTED_MIN" in
  "1.0") EXPECTED_CB="VersionTLS10" ;;
  "1.1") EXPECTED_CB="VersionTLS11" ;;
  "1.3") EXPECTED_CB="VersionTLS13" ;;
  *)     EXPECTED_CB="VersionTLS12" ;;
esac
echo "Waiting for TA ConfigMap to have min_version=$EXPECTED_CB"

# Wait for the operator to be ready after the TLS profile change triggers a restart.
for i in $(seq 1 60); do
  ready=$(kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator \
    -o jsonpath='{range .items[*]}{.status.phase} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    | grep -c "Running True" || true)
  if [ "$ready" -ge 1 ]; then
    echo "Operator pod is ready"
    break
  fi
  echo "Waiting for operator pod to be ready... ($i/60)"
  sleep 5
done

# Wait for the TA ConfigMap to reference the new TLS profile.
for i in $(seq 1 60); do
  CM_NAME=$(kubectl get configmap -n "$NAMESPACE" \
    -l app.kubernetes.io/component=opentelemetry-targetallocator \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$CM_NAME" ]; then
    ACTUAL_MIN=$(kubectl get configmap "$CM_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.data.targetallocator\.yaml}' 2>/dev/null \
      | yq -r '.https.min_version' 2>/dev/null || true)
    if [ "$ACTUAL_MIN" = "$EXPECTED_CB" ]; then
      echo "TA ConfigMap $CM_NAME has expected min_version=$ACTUAL_MIN"
      break
    fi
    echo "TA ConfigMap has min_version=$ACTUAL_MIN, expected $EXPECTED_CB ($i/60)"
  else
    echo "TA ConfigMap not found yet ($i/60)"
  fi
  sleep 5
done

# Wait for the TA deployment rollout to complete.
kubectl rollout status deployment/ta-tls-test-targetallocator -n "$NAMESPACE" --timeout=120s

# Wait for the collector statefulset rollout to complete.
kubectl rollout status statefulset/ta-tls-test-collector -n "$NAMESPACE" --timeout=120s
