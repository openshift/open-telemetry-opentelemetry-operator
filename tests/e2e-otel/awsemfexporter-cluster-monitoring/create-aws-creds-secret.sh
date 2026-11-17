#!/bin/bash

# Fetch AWS credentials based on CLUSTER_PROFILE_DIR variable
if [ -n "${CLUSTER_PROFILE_DIR}" ]; then
    # the shared credentials file allows spaces around "=", values are kept verbatim
    AWS_ACCESS_KEY_ID=$(sed -n 's/^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
    AWS_SECRET_ACCESS_KEY=$(sed -n 's/^[[:space:]]*aws_secret_access_key[[:space:]]*=[[:space:]]*//p' "${CLUSTER_PROFILE_DIR}/.awscred" | head -n1 | sed 's/[[:space:]]*$//')
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

# Create the Kubernetes secret from stdin so that the credentials do not appear in a command line
if ! oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
type: Opaque
stringData:
  access_key_id: "${AWS_ACCESS_KEY_ID}"
  secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
EOF
then
    echo "Failed to create AWS credentials secret"
    exit 1
fi

echo "AWS secret aws-credentials created successfully"
