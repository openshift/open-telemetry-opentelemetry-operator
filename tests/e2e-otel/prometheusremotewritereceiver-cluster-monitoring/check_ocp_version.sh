#!/bin/bash
# The Cluster Monitoring Operator supports remoteWrite[].messageVersion (remote write v2)
# starting with OpenShift 5.0. Fail early with a clear message on older clusters.
set -euo pipefail
version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}')
major=${version%%.*}
if [[ -z "$major" || "$major" -lt 5 ]]; then
  echo "OpenShift $version does not support remote write v2 (messageVersion) in the Cluster Monitoring Operator; OpenShift 5.0 or later is required. Skip this test on older clusters."
  exit 1
fi
echo "OpenShift $version supports remote write v2 in the Cluster Monitoring Operator."
