/**
 * `npm run login`: open a visible browser on the console, let a human log in, and save the session.
 *
 *   AUTH_STATE_FILE=/tmp/otel-ui-auth.json npm run login
 *   AUTH_STATE_FILE=/tmp/otel-ui-auth.json OTEL_UI_NAMESPACE=<ns> npx playwright test
 *
 * Useful for local development: the password is typed by you and never handled by the test code.
 */
import { chromium } from '@playwright/test';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { skipWelcomeTour } from './console-login';
import { authStateFile, consoleUrl } from './env';

async function main(): Promise<void> {
  const baseUrl = consoleUrl();
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();
  await page.goto(baseUrl);

  console.log(`Log in to ${baseUrl} in the browser window (you have 5 minutes)...`);
  await page.locator('[data-test="username"]').first().waitFor({ state: 'visible', timeout: 5 * 60_000 });
  await skipWelcomeTour(page);

  fs.mkdirSync(path.dirname(authStateFile), { recursive: true, mode: 0o700 });
  await context.storageState({ path: authStateFile });
  fs.chmodSync(authStateFile, 0o600);
  console.log(`Session saved to ${authStateFile}`);
  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
