FROM scratch

ARG VERSION=0.158.1

# Core bundle labels.
LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
LABEL operators.operatorframework.io.bundle.package.v1=opentelemetry-product
LABEL operators.operatorframework.io.bundle.channels.v1=stable
LABEL operators.operatorframework.io.metrics.builder=operator-sdk-v1.29.0
LABEL operators.operatorframework.io.metrics.mediatype.v1=metrics+v1
LABEL operators.operatorframework.io.metrics.project_layout=go.kubebuilder.io/v3

# Labels for testing.
LABEL operators.operatorframework.io.test.mediatype.v1=scorecard+v1
LABEL operators.operatorframework.io.test.config.v1=tests/scorecard/

# Red Hat / OpenShift labels.
LABEL com.redhat.openshift.versions=v4.12
LABEL release="${VERSION}" \
      version="${VERSION}" \
      cpe="cpe:/a:redhat:openshift_distributed_tracing:3.11::el9" \
      com.redhat.component="opentelemetry-operator-bundle-container" \
      name="rhosdt/opentelemetry-operator-bundle" \
      distribution-scope="public" \
      description="Bundle for OpenTelemetry operator" \
      io.k8s.description="Bundle for OpenTelemetry operator" \
      io.openshift.tags="tracing" \
      io.k8s.display-name="OpenTelemetry Operator Bundle" \
      url="https://github.com/open-telemetry/opentelemetry-operator" \
      vendor="Red Hat, Inc." \
      summary="OpenTelemetry operator bundle" \
      maintainer="support@redhat.com"

# Copy files to locations specified by labels.
COPY ./manifests /manifests/
COPY ./metadata /metadata/
COPY ./tests/scorecard /tests/scorecard/
