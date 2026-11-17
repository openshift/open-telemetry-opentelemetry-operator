#!/bin/bash

region="us-east-2"

# Fetch AWS credentials based on CLUSTER_PROFILE_DIR variable
if [ -n "${CLUSTER_PROFILE_DIR}" ]; then
    AWS_ACCESS_KEY_ID=$(grep "aws_access_key_id=" "${CLUSTER_PROFILE_DIR}/.awscred" | cut -d '=' -f2)
    AWS_SECRET_ACCESS_KEY=$(grep "aws_secret_access_key=" "${CLUSTER_PROFILE_DIR}/.awscred" | cut -d '=' -f2)
elif oc get secret aws-creds -n kube-system >/dev/null 2>&1; then
    AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_access_key_id' | base64 -d)
    if [ $? -ne 0 ]; then
        echo "Failed to fetch AWS_ACCESS_KEY_ID"
        exit 1
    fi

    AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o json | jq -r '.data.aws_secret_access_key' | base64 -d)
    if [ $? -ne 0 ]; then
        echo "Failed to fetch AWS_SECRET_ACCESS_KEY"
        exit 1
    fi
elif aws sts get-caller-identity >/dev/null 2>&1; then
    # Check if we're already logged into AWS and can get credentials
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "AWS CLI is configured but cannot retrieve access key credentials (may be using IAM roles or other auth method)"
        echo "Please ensure AWS credentials are available as access key ID and secret access key"
        exit 1
    fi
    
    echo "Using AWS credentials from AWS CLI configuration"
else
    echo "No AWS credentials found. Please ensure one of the following:"
    echo "1. CLUSTER_PROFILE_DIR is set with .awscred file"
    echo "2. aws-creds secret exists in kube-system namespace"
    echo "3. AWS CLI is configured with valid credentials"
    exit 1
fi

export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
export AWS_DEFAULT_REGION=${region}
# The chainsaw step allows 8 minutes; stop polling with a minute to spare.
script_deadline=$(( $(date +%s) + 420 ))

# Check if retentionInDays is 365
RETENTION_DAYS=$(aws logs describe-log-groups --log-group-name-prefix $log_group_name --region $region --query "logGroups[?logGroupName=='$log_group_name'].retentionInDays" --output text)
if [ "$RETENTION_DAYS" == "1" ]; then
    echo "retentionInDays is 1"
else
    echo "retentionInDays is not 1"
    exit 1
fi

# Check that a log record contains the app log line. The EMF exporter writes its metric records to
# the same log stream, so the app log line is not always the first record. CloudWatch Logs can lag
# behind the exporter, so poll for it.
logs_found=false
for attempt in $(seq 1 18); do
    # Read the whole stream from the start: the CLI follows the page tokens (a page can be partial or empty), and
    # the end time keeps the paging finite while the exporters still write.
    MESSAGES=$(aws logs get-log-events --log-group-name $log_group_name --log-stream-name $log_stream_name --region $region --start-from-head --end-time "$(( $(date +%s) * 1000 ))" --query "events[*].message" --output text)
    if [[ "$MESSAGES" == *"SVTLogger - INFO - app-log-plaintext-rc-"* ]]; then
        logs_found=true
        break
    fi
    echo "Attempt $attempt/18: no app logs in CloudWatchLogs yet, retrying in 10s..."
    sleep 10
done
if [ "$logs_found" = true ]; then
    echo "App logs found in CloudWatchLogs"
else
    echo "No app logs found in CloudWatchLogs"
    exit 1
fi

# Check that the EMF exporter published the telemetrygen metric during this test run. Only data
# points since the metrics job was created count: list-metrics would also return the metric that
# an earlier run published up to two weeks ago. A new metric can take a few minutes to appear.
run_start=$(kubectl get job telemetrygen-metrics -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}')
if [ -z "$run_start" ]; then
    echo "Could not determine the start of the test run. Script failed."
    exit 1
fi
search="SEARCH('{Tracing-EMF,telemetrygen} MetricName=\"gen\" \"telemetrygen\"=\"metrics\"', 'SampleCount', 60)"
found=false
attempt=0
while [ "$(date +%s)" -lt "$script_deadline" ]; do
    attempt=$((attempt + 1))
    # prints the number of data points and the status codes of the query results
    if ! output=$(aws cloudwatch get-metric-data --region "$region" --start-time "$run_start" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --metric-data-queries "[{\"Id\":\"q\",\"Expression\":$(printf '%s' "$search" | jq -R .),\"Period\":60}]" \
        --query "[sum(MetricDataResults[].length(Values)), join(',', MetricDataResults[].StatusCode)]" --output text 2>&1); then
        # credential and permission errors do not go away with retries
        if echo "$output" | grep -q -E 'AccessDenied|UnrecognizedClient|InvalidClientTokenId|ExpiredToken|SignatureDoesNotMatch'; then
            echo "The CloudWatch query failed: $output. Script failed."
            exit 1
        fi
        echo "Attempt $attempt: the CloudWatch query failed, retrying in 10s: $output"
    else
        count=$(echo "$output" | awk '{print $1}')
        status=$(echo "$output" | awk '{print $2}')
        if [[ "$status" == *Forbidden* ]]; then
            echo "CloudWatch returned the status $status for the metric query. Script failed."
            exit 1
        fi
        if [ -n "$count" ] && [ "$count" != "None" ] && [ "$count" -gt 0 ] 2>/dev/null; then
            found=true
            break
        fi
        echo "Attempt $attempt: no data points since $run_start for the metric with dimension Name 'telemetrygen' and value 'metrics' yet (status $status), retrying in 10s..."
    fi
    sleep 10
done

if [ "$found" = true ]; then
    echo "The metric with dimension Name 'telemetrygen' and value 'metrics' exists. Script succeeded."
else
    echo "The metric with dimension Name 'telemetrygen' and value 'metrics' does not exist. Script failed."
    exit 1
fi
