import { Page } from '@playwright/test';

// A fresh cluster serves the console slowly. The Cypress suite of distributed-tracing-console-plugin waits up to
// 120 seconds for the same thing.
const LOGIN_TIMEOUT = 120_000;

/**
 * Log in to the OpenShift web console as the `kube:admin` user.
 *
 * The selectors are the ones that the Cypress login of distributed-tracing-console-plugin relies on in OpenShift
 * CI across OCP versions. The OAuth login page first shows an identity provider chooser when more than one
 * provider is configured (for example `kube:admin` and an htpasswd provider); with a single provider, and on
 * HyperShift, the form is shown directly.
 */
export async function loginAsKubeadmin(page: Page, baseUrl: string, password: string): Promise<void> {
  try {
    await login(page, baseUrl, password);
  } catch (error) {
    throw withoutSecret(error, password);
  }
}

/**
 * When `fill` fails (for example on a timeout) Playwright puts the value in the error message, in the call log
 * (`fill("...")`). The message ends up in the build log and in the JUnit file, so it must not carry the password.
 * A new error is thrown: its stack does not contain the value either.
 */
function withoutSecret(error: unknown, secret: string): Error {
  const message = error instanceof Error ? error.message : String(error);
  if (!secret) {
    return new Error(message);
  }
  const escaped = JSON.stringify(secret).slice(1, -1);
  return new Error(message.split(secret).join('[REDACTED]').split(escaped).join('[REDACTED]'));
}

async function login(page: Page, baseUrl: string, password: string): Promise<void> {
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });

  const providerLink = page.getByRole('link', { name: 'kube:admin' });
  const usernameField = page.locator('#inputUsername');
  await providerLink.or(usernameField).first().waitFor({ state: 'visible', timeout: LOGIN_TIMEOUT });
  if (await providerLink.isVisible()) {
    await providerLink.click();
  }

  await usernameField.fill('kubeadmin');
  await page.locator('#inputPassword').fill(password);
  await page.locator('button[type=submit]').click();

  // The masthead shows the user name once the OAuth flow is done and the console has loaded.
  await page.locator('[data-test="username"]').first().waitFor({ state: 'visible', timeout: LOGIN_TIMEOUT });
  await skipWelcomeTour(page);
}

/**
 * A user who logs in for the first time gets a dialog that covers the page: the guided tour, or on OCP 4.22+
 * "Welcome to the new OpenShift experience". Skipping it is remembered for the user, so it only shows up in
 * the first session.
 */
export async function skipWelcomeTour(page: Page): Promise<void> {
  const skip = page.locator('[data-test="tour-step-footer-secondary"]');
  const close = page.locator('.pf-v6-c-modal-box button[aria-label="Close"], .pf-v5-c-modal-box button[aria-label="Close"]');
  try {
    await skip.or(close).first().waitFor({ state: 'visible', timeout: 15_000 });
  } catch {
    return; // No dialog: the tour was skipped before.
  }
  const button = (await skip.isVisible()) ? skip : close.first();
  await button.click();
  await button.waitFor({ state: 'hidden', timeout: 10_000 });
}
