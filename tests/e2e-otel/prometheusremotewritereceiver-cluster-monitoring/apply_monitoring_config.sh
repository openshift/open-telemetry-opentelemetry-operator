#!/bin/bash
# Apply the monitoring config maps with oc instead of a chainsaw apply step, so that chainsaw
# does not delete them at the end of the test; cleanup_monitoring_config.sh restores them.
set -euo pipefail
oc apply -f cluster-monitoring-config.yaml -f user-workload-monitoring-config.yaml
