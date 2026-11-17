#!/bin/bash
# Save the monitoring config maps before the test changes them, so that the cleanup can restore
# them. The state file records, per config map, "saved" (a copy exists) or "absent" (NotFound):
# it is emptied first, so a cleanup that runs after a failed backup finds no entry and does not
# touch the config map, and a backup of an earlier run can never be applied. A state file that
# still has entries means that the cleanup of an earlier run did not restore the config maps: the
# backup then stops instead of saving the test configuration as the new baseline. Any read error
# other than NotFound, and any failed write of the backup files, fails the test before it changes
# anything.
set -euo pipefail
backup_dir="/tmp/monitoring-config-backup-${NAMESPACE:-chainsaw}"
mkdir -p "$backup_dir"
if [ -s "$backup_dir/state" ]; then
  echo "FAIL: $backup_dir/state still holds the restore state of an earlier run whose cleanup did not complete."
  echo "Restore the monitoring config maps first: NAMESPACE=${NAMESPACE:-chainsaw} ./cleanup_monitoring_config.sh"
  exit 1
fi
: > "$backup_dir/state"
for cm in "cluster-monitoring-config openshift-monitoring" "user-workload-monitoring-config openshift-user-workload-monitoring"; do
  set -- $cm
  if output=$(oc get configmap "$1" -n "$2" -o json 2>&1); then
    if ! echo "$output" | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields, .metadata.generation)' > "$backup_dir/$1.json" || [ ! -s "$backup_dir/$1.json" ]; then
      echo "FAIL: could not save $2/$1"
      exit 1
    fi
    echo "$1=saved" >> "$backup_dir/state"
    echo "Saved $2/$1 to $backup_dir/$1.json"
  elif echo "$output" | grep -q 'NotFound'; then
    echo "$1=absent" >> "$backup_dir/state"
    echo "$2/$1 does not exist, nothing to save"
  else
    echo "FAIL: could not read $2/$1: $output"
    exit 1
  fi
done
