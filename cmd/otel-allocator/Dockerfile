# Build the target-allocator binary
FROM registry.redhat.io/ubi9/ubi:latest AS builder

WORKDIR /opt/app-root/src
USER root

COPY . /opt/app-root/src/
# this directory is checked by ecosystem-cert-preflight-checks task in Konflux
COPY LICENSE /licenses/

RUN CGO_ENABLED=0 GOFIPS140=certified go build -C ./cmd/otel-allocator -mod=mod -tags no_openssl -o ./opentelemetry-target-allocator -trimpath -ldflags "-s -w"

# Use ubi-micro as the target base for a minimal runtime image
FROM registry.redhat.io/ubi9/ubi-micro:latest AS target-base

FROM scratch
WORKDIR /
COPY --from=target-base / /

ARG VERSION=0.158.1

RUN mkdir /licenses
COPY LICENSE /licenses/.
COPY --from=builder /opt/app-root/src/cmd/otel-allocator/opentelemetry-target-allocator /usr/bin/opentelemetry-target-allocator

ENV GODEBUG=fips140=auto
ARG USER_UID=1001
USER ${USER_UID}
ENTRYPOINT ["/usr/bin/opentelemetry-target-allocator"]

LABEL release="${VERSION}" \
      version="${VERSION}" \
      cpe="cpe:/a:redhat:openshift_distributed_tracing:3.11::el9" \
      vendor="Red Hat, Inc." \
      distribution-scope="public" \
      url="https://github.com/open-telemetry/opentelemetry-operator" \
      com.redhat.component="opentelemetry-target-allocator-rhel9-container" \
      name="rhosdt/opentelemetry-target-allocator-rhel9" \
      summary="OpenTelemetry Target allocator" \
      description="Prometheus target allocator for the OpenTelemetry collector" \
      io.k8s.description="Target allocator for the OpenTelemetry collector." \
      io.openshift.expose-services="80:http" \
      io.openshift.tags="monitoring" \
      io.k8s.display-name="OpenTelemetry Target allocator" \
      maintainer="support@redhat.com"
