import { defineConfig, devices } from '@playwright/test';
import * as path from 'node:path';
import { artifactDir, authStateFile, browserProxy, chromiumArgs, consoleUrl, inCI } from './support/env';

export default defineConfig({
  testDir: './specs',
  globalSetup: './global-setup.ts',
  globalTeardown: './global-teardown.ts',

  // The data spec waits for the first scrape of the user workload monitoring stack.
  timeout: 10 * 60_000,
  // Same values as the Cypress suite of distributed-tracing-console-plugin, which runs on the same CI clusters
  // (defaultCommandTimeout 40s, pageLoadTimeout 120s).
  expect: { timeout: 30_000 },

  // The specs share the collectors and are meant to run in order.
  fullyParallel: false,
  workers: 1,
  retries: inCI ? 1 : 0,

  reporter: [
    ['list'],
    // Not `junit_otel_*`: qe-agent maps that prefix to the operator's own chainsaw suite.
    ['junit', { outputFile: path.join(artifactDir, 'junit_console_ui_otel_dashboard.xml') }],
    ['html', { open: 'never', outputFolder: path.join(artifactDir, 'playwright-report') }],
  ],
  outputDir: path.join(artifactDir, 'test-results'),

  use: {
    baseURL: consoleUrl(),
    // OpenShift consoles on CI clusters use a self-signed ingress certificate.
    ignoreHTTPSErrors: true,
    // The console uses `data-test` attributes.
    testIdAttribute: 'data-test',
    storageState: authStateFile,
    actionTimeout: 40_000,
    navigationTimeout: 120_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    launchOptions: { args: chromiumArgs, proxy: browserProxy() },
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1600, height: 1400 } },
    },
  ],
});
