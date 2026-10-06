# OpenTelemetry Collector dashboard (OpenShift console)

Verifies the **OpenTelemetry Collector** dashboard that the OpenTelemetry operator publishes for the OpenShift
web console (**Observe > Dashboards**). It replaces the manual `otel-qe-collector-dashboard-manual` procedure.

The test is a Chainsaw test that prepares the data and then runs [Playwright](https://playwright.dev/) in the
`ui/` directory. The data is generated the same way as in the operator's own e2e test
(`opentelemetry-operator/tests/e2e-openshift/monitoring`), each fixture file names its source.

| Step | What it does |
|---|---|
| `enable-user-workload-monitoring` | Enables OpenShift user workload monitoring (`00-*`). |
| `deploy-collectors` | Deploys `cluster-collector` (with an exporter that always fails) and an idle `second` collector, both with `enableMetrics: true` (`01-*`). |
| `generate-telemetry` | Three `telemetrygen` Jobs send traces, metrics and logs to `cluster-collector` for 15 minutes (`02-*`). |
| `wait-for-dashboard-metrics` | Waits until every series the dashboard queries exists in Thanos (`03-*`, `check_metrics.sh`). |
| `verify-dashboard-in-console` | Runs the Playwright specs in `ui/specs`. |

## What the specs check

1. The operator published `openshift-config-managed/opentelemetry-collector` with the console dashboard label.
2. The dashboard is listed under Observe > Dashboards and opens.
3. The three rows (Metrics, Traces, Resource usage) with three panels each are drawn.
4. Every panel shows the series produced by the generated telemetry (one spec per panel).
5. The variable dropdowns list the deployed collectors; selecting a collector instance filters the panels.

## Prerequisites

- OpenShift cluster with the OpenTelemetry operator installed and `OPENSHIFT_CREATE_DASHBOARD=true` (the default of
  the Red Hat build and of the OpenShift bundle). The dashboard is deleted when the operator shuts down.
- `KUBECONFIG` of a cluster admin, `oc`, [Chainsaw](https://kyverno.github.io/chainsaw/), Node.js 20+ and
  `npx playwright install chromium` in `ui/` (once, for local runs).
- A console login, see below. Chainsaw and the specs need cluster-admin: without cluster-wide access to the
  monitoring API the console shows no data for "All Projects".

## Run

From the repository root:

```bash
export KUBECONFIG=/path/to/kubeconfig
export KUBEADMIN_PASSWORD_FILE=/path/to/kubeadmin-password
chainsaw test --config .chainsaw.yaml --test-dir tests/e2e-otel-ui/collector-dashboard
```

Run `chainsaw` from the repository root, where `.chainsaw.yaml` is. The `script` steps of the test (`check_metrics.sh`,
`npm ci` and `npx playwright test` in `ui/`) run in the test directory, `tests/e2e-otel-ui/collector-dashboard`,
whatever the directory `chainsaw` was started from.

Environment variables:

| Variable | Purpose |
|---|---|
| `KUBEADMIN_PASSWORD_FILE` | File with the kubeadmin password; the specs log in as `kube:admin`. `${SHARED_DIR}/kubeadmin-password` is the fallback (OpenShift CI). |
| `AUTH_STATE_FILE` | A saved browser session instead of a password, see below. |
| `BASE_URL` | Console URL. Default: `oc whoami --show-console`. |
| `HTTPS_PROXY`, `NO_PROXY` | Proxy for the browser (also the lower-case names). OpenShift CI sets them through `${SHARED_DIR}/proxy-conf.sh` for clusters behind a proxy. |
| `ARTIFACT_DIR` | Where JUnit (`junit_console_ui_otel_dashboard.xml`), the HTML report, traces, screenshots and videos go. Default `ui/artifacts`. |
| `OTEL_UI_DATA_TIMEOUT_SECONDS` | How long a panel may take to show data (default 360). |
| `OTEL_UI_NAMESPACE` | Namespace of the collectors. Set by the Chainsaw test; set it yourself when running Playwright alone. |

**Logging in without a password file:** `cd ui && AUTH_STATE_FILE=/tmp/otel-ui-auth.json npm run login` opens a
browser, you log in, and the session is saved. Then run with the same `AUTH_STATE_FILE`.

**Fast loop while writing specs:** keep the data and iterate on the specs only.

```bash
chainsaw test --config .chainsaw.yaml --test-dir tests/e2e-otel-ui/collector-dashboard --skip-delete   # note the chainsaw-* namespace
cd tests/e2e-otel-ui/collector-dashboard/ui
npm ci
OTEL_UI_NAMESPACE=chainsaw-xxxx npx playwright test          # or --ui / --headed
```

The telemetry generators stop after 15 minutes; delete and re-apply `02-generate-telemetry.yaml` to refresh the data.

The login runs in a browser context without tracing or screenshots, so the password cannot end up in the published
artifacts.

## Known dashboard behaviour (verified on OCP 4.22, operator/collector 0.158)

- **"Metrics Exported vs Failed / second" can be empty for a healthy collector.** The `metric exporter` variable
  is built from `otelcol_exporter_send_failed_metric_points`, which only exists once an export failed. Without
  values the console sends `undefined` queries ("No datapoints found.", and the `metric exporter` dropdown is
  hidden) although `otelcol_exporter_sent_metric_points` has data. The traces panel uses `otelcol_exporter_sent_spans`
  and works. Whether the series exists depends on the collector's history, so `cluster-collector` has a second,
  unreachable exporter (`otlp/unreachable` in `01-otel-collector.yaml`): its failures make the series exist in
  every run, the specs can assert both "sent" and "failed" legends, and the result does not depend on timing.
  This works around the defect in the dashboard, it does not test that it is gone.
- The "dropped" series of both Processor panels cannot exist: the memory limiter processor has no dropped metric.
  "Refused" series only exist after a refusal. The specs assert the "accepted", "sent" and "failed" series.
- The dashboard is only offered for **All Projects**. With a concrete project selected the console shows the
  namespace-scoped dashboards and replaces this one, so the specs always open it with `project-dropdown-value=#ALL_NS#`.
- Panels are rendered lazily when they scroll into view; `reveal()` scrolls to a panel before asserting on it.
- The selected dashboard is the *value* of a PatternFly typeahead input, not its text.
- A new console user gets a "Welcome to the new OpenShift experience" dialog; the login helper skips it.
- The console uses `data-test` attributes (`testIdAttribute: 'data-test'` in `playwright.config.ts`).

## CI

`openshift/release` runs this test in the `opentelemetry-ui-tests` job of the OpenTelemetry operator
(variant `upstream-ui-ocp-4.22-amd64`): the operator bundle built from the PR is installed, then the
`distributed-tracing-tests-opentelemetry-ui-upstream` step runs the test. The step fails when a test fails, and so does
the job. When it does, the `openshift-observability-qe-agent` post step triages the failure with the `otel-ui` skill
and files a bug in the Jira project OOC for a product bug.
The step runs in the `playwright-base` image built from `../Dockerfile.playwright`
(`quay.io/redhat-distributed-tracing-qe/playwright-base`, mirrored to the CI registry as `ci/playwright-base`),
takes the tests from the `main` branch of this repository and logs in with the kubeadmin password of
the CI cluster. The step needs no cluster variables of its own, it works like the tracing UI plugin (Cypress)
steps: ci-operator injects `KUBECONFIG` and `KUBEADMIN_PASSWORD_FILE` (`${SHARED_DIR}/kubeadmin-password`, or the
Hive admin secret for claimed clusters) into every multi-stage step, and the step reads the console host from the
`console` route. The login page selectors and timeouts are the ones of that Cypress login
(`distributed-tracing-console-plugin/tests/cypress/support/commands.ts`).

The same image is the agent image (`obs-tests-runner`) of the job, like `cypress-base` for the tracing UI plugin jobs
(the job has its own variant configuration for that): the qe-agent post step runs in it, so it has the Claude Code CLI
and `yq` besides the tools and the browser of the step, and the agent can rerun the specs.

The version in `Dockerfile.playwright` (`PLAYWRIGHT_VERSION`) must equal `@playwright/test` in `ui/package.json`:
Playwright only launches the browser revision it was released with. To publish a new image:

```bash
podman build --platform linux/amd64 -f tests/e2e-otel-ui/Dockerfile.playwright \
  -t quay.io/redhat-distributed-tracing-qe/playwright-base:1.63.0 tests/e2e-otel-ui
podman tag quay.io/redhat-distributed-tracing-qe/playwright-base:1.63.0 quay.io/redhat-distributed-tracing-qe/playwright-base:latest
podman push quay.io/redhat-distributed-tracing-qe/playwright-base:1.63.0
podman push quay.io/redhat-distributed-tracing-qe/playwright-base:latest
```
