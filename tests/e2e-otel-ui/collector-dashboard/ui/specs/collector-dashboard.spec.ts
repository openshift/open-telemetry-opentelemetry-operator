import { expect, test } from '@playwright/test';
import {
  COLLECTOR_SERVICE,
  CollectorDashboardPage,
  DASHBOARD_ID,
  DASHBOARD_TITLE,
  PANELS,
  RowId,
  SECOND_COLLECTOR_SERVICE,
} from '../pages/collector-dashboard.page';
import { testNamespace } from '../support/env';
import { ocGetJson } from '../support/oc';

const namespace = testNamespace();

// How long the panels may take to show data: user workload monitoring has to scrape the collectors and the
// console refreshes every 30 seconds. The Chainsaw test already waited for the series, so this is a safety net.
// OTEL_UI_DATA_TIMEOUT_SECONDS shortens it for experiments.
const DATA_TIMEOUT = Number(process.env.OTEL_UI_DATA_TIMEOUT_SECONDS ?? 360) * 1000;

test.describe.configure({ mode: 'serial' });

test.describe('OpenTelemetry Collector dashboard', () => {
  test('the operator publishes the dashboard ConfigMap', async () => {
    let configMap: { metadata: { labels?: Record<string, string> }; data?: Record<string, string> };
    try {
      configMap = ocGetJson('configmap', DASHBOARD_ID, '-n', 'openshift-config-managed');
    } catch (error) {
      throw new Error(
        `ConfigMap openshift-config-managed/${DASHBOARD_ID} not found. The operator creates it when it runs ` +
          `with OPENSHIFT_CREATE_DASHBOARD=true and removes it when it shuts down.\n${error}`,
      );
    }
    expect(configMap.metadata.labels?.['console.openshift.io/dashboard']).toBe('true');
    const dashboard = JSON.parse(configMap.data?.['otel.json'] ?? '{}');
    expect(dashboard.title).toBe(DASHBOARD_TITLE);
  });

  test('is listed under Observe > Dashboards and opens', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Observe' }).or(page.getByRole('link', { name: 'Observe' })).first().click();
    await page.getByRole('link', { name: 'Dashboards', exact: true }).click();
    await expect(page).toHaveURL(/\/monitoring\/dashboards/);

    const dashboard = new CollectorDashboardPage(page);
    await dashboard.dashboardPicker.getByRole('button').click();
    // The option also contains the "opentelemetry" tag of the dashboard.
    await page.getByRole('option', { name: /^OpenTelemetry Collector/ }).click();

    await expect(page).toHaveURL(new RegExp(`/monitoring/dashboards/${DASHBOARD_ID}`));
    await dashboard.expectDashboardSelected();
  });

  test('shows three rows with three panels each', async ({ page }) => {
    const dashboard = new CollectorDashboardPage(page);
    await dashboard.open();

    for (const row of ['metrics', 'traces', 'resource-usage'] as RowId[]) {
      await expect(dashboard.row(row)).toBeVisible();
      await expect(dashboard.row(row).locator('[data-test$="-chart"]')).toHaveCount(3);
    }
    for (const panel of PANELS) {
      await dashboard.reveal(panel);
    }
  });

  test.describe('panels show the metrics of the generated telemetry', () => {
    for (const panel of PANELS) {
      test(`${panel.row}: ${panel.title}`, async ({ page }) => {
        const dashboard = new CollectorDashboardPage(page);
        await expect(async () => {
          await dashboard.open();
          await dashboard.expectPanelHasData(panel, namespace);
        }).toPass({ timeout: DATA_TIMEOUT, intervals: [5_000, 15_000, 30_000] });
      });
    }
  });

  test('variable dropdowns list the deployed collectors', async ({ page }) => {
    const dashboard = new CollectorDashboardPage(page);
    await dashboard.open();

    expect(await dashboard.variableOptions('span exporter')).toContain('debug');
    // Built from the failed series, so it only lists exporters that failed: the unreachable one.
    expect(await dashboard.variableOptions('metric exporter')).toContain('otlp/unreachable');
    expect(await dashboard.variableOptions('metric receiver')).toContain('otlp');
    expect(await dashboard.variableOptions('span receiver')).toContain('otlp');
    expect(await dashboard.variableOptions('span processor')).toContain('memory_limiter');
    expect(await dashboard.variableOptions('metric processor')).toContain('memory_limiter');
    expect(await dashboard.variableOptions('namespace')).toContain(namespace);
    expect(await dashboard.variableOptions('collector instance')).toEqual(
      expect.arrayContaining(['All', COLLECTOR_SERVICE, SECOND_COLLECTOR_SERVICE]),
    );
  });

  test('the collector instance variable filters the panels', async ({ page }) => {
    const dashboard = new CollectorDashboardPage(page);
    await dashboard.open();
    const memory = PANELS.find((panel) => panel.title.startsWith('Total physical memory'))!;
    const panel = await dashboard.reveal(memory);
    await expect(panel).toContainText(`${COLLECTOR_SERVICE}/${namespace}`);
    await expect(panel).toContainText(`${SECOND_COLLECTOR_SERVICE}/${namespace}`);

    await dashboard.selectVariable('collector instance', SECOND_COLLECTOR_SERVICE);
    await expect(page).toHaveURL(/collector\+instance=second-collector-monitoring/);
    await expect(panel).toContainText(`${SECOND_COLLECTOR_SERVICE}/${namespace}`);
    await expect(panel).not.toContainText(`${COLLECTOR_SERVICE}/${namespace}`);

    await dashboard.selectVariable('collector instance', COLLECTOR_SERVICE);
    await expect(panel).toContainText(`${COLLECTOR_SERVICE}/${namespace}`);
    await expect(panel).not.toContainText(`${SECOND_COLLECTOR_SERVICE}/${namespace}`);
  });

  test('the namespace variable keeps the collectors of that namespace', async ({ page }) => {
    const dashboard = new CollectorDashboardPage(page);
    await dashboard.open();
    await dashboard.selectVariable('namespace', namespace);
    await expect(page).toHaveURL(new RegExp(`[?&]namespace=${namespace}`));

    const memory = PANELS.find((panel) => panel.title.startsWith('Total physical memory'))!;
    const panel = await dashboard.reveal(memory);
    await expect(panel).toContainText(`${COLLECTOR_SERVICE}/${namespace}`);
    await expect(panel).toContainText(`${SECOND_COLLECTOR_SERVICE}/${namespace}`);
  });
});
