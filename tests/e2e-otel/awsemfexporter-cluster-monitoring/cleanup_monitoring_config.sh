#!/bin/bash
# Restore the monitoring config maps from the state recorded by backup_monitoring_config.sh in
# this run: "saved" applies the copy back, "absent" deletes the config map the test created, and a
# config map without an entry (the backup failed before recording it) is left untouched. The state
# file is emptied once both config maps are back in place so that a later run cannot reuse it; when
# a restore fails the state is kept so that this script can be run again by hand. Also remove the
# cluster role binding subject the verification script added: a binding that does not exist or does
# not hold the subject means there is nothing to remove, any other lookup error fails the cleanup.
backup_dir="/tmp/monitoring-config-backup-${NAMESPACE:-chainsaw}"
status=0
cm_status=0
for cm in "cluster-monitoring-config openshift-monitoring" "user-workload-monitoring-config openshift-user-workload-monitoring"; do
  set -- $cm
  state=$(grep "^$1=" "$backup_dir/state" 2>/dev/null | cut -d= -f2)
  case "$state" in
    saved)
      if [ -s "$backup_dir/$1.json" ] && oc apply -f "$backup_dir/$1.json"; then echo "Restored $2/$1"; else echo "FAIL: could not restore $2/$1"; cm_status=1; fi ;;
    absent)
      if oc delete configmap "$1" -n "$2" --ignore-not-found; then echo "Deleted $2/$1 (it did not exist before the test)"; else echo "FAIL: could not delete $2/$1"; cm_status=1; fi ;;
    *)
      echo "No backup state for $2/$1 (the backup did not complete), leaving it untouched" ;;
  esac
done
if [ "$cm_status" = 0 ]; then
  : > "$backup_dir/state"
else
  status=1
  echo "Restore state kept in $backup_dir/state; run NAMESPACE=${NAMESPACE:-chainsaw} ./cleanup_monitoring_config.sh again to retry"
fi
if [ -n "${NAMESPACE:-}" ]; then
  subject="system:serviceaccount:$NAMESPACE:e2e-test-metrics-reader"
  if binding=$(oc get clusterrolebinding cluster-monitoring-view -o json 2>&1); then
    if echo "$binding" | jq -e --arg ns "$NAMESPACE" '.subjects[]? | select(.kind == "ServiceAccount" and .name == "e2e-test-metrics-reader" and .namespace == $ns)' >/dev/null; then
      if oc adm policy remove-cluster-role-from-user cluster-monitoring-view "$subject"; then echo "Removed $subject from cluster-monitoring-view"; else echo "FAIL: could not remove $subject from cluster-monitoring-view"; status=1; fi
    else
      echo "$subject is not a subject of cluster-monitoring-view, nothing to remove"
    fi
  elif echo "$binding" | grep -q 'NotFound'; then
    echo "Cluster role binding cluster-monitoring-view does not exist, nothing to remove"
  else
    echo "FAIL: could not read cluster role binding cluster-monitoring-view: $binding"
    status=1
  fi
fi
exit $status
