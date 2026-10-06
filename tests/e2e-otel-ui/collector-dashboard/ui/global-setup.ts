import { chromium } from '@playwright/test';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { loginAsKubeadmin } from './support/console-login';
import { authStateFile, browserProxy, chromiumArgs, consoleUrl, kubeadminPasswordFile } from './support/env';

/**
 * Log in once and store the session for all specs.
 *
 * - $AUTH_STATE_FILE set: use that session (created with `npm run login`), no password needed.
 * - Otherwise log in as kube:admin with the password from the file described in support/env.ts.
 *
 * The login runs in a context without tracing, videos or screenshots, so the password can never end
 * up in the artifacts that OpenShift CI publishes.
 */
export default async function globalSetup(): Promise<void> {
  if (process.env.AUTH_STATE_FILE) {
    if (!fs.existsSync(authStateFile)) {
      throw new Error(`AUTH_STATE_FILE=${authStateFile} does not exist. Create it with \`npm run login\`.`);
    }
    return;
  }

  const passwordFile = kubeadminPasswordFile();
  if (!passwordFile) {
    throw new Error(
      'No console credentials. Set KUBEADMIN_PASSWORD_FILE (or SHARED_DIR with a kubeadmin-password file), ' +
        'or set AUTH_STATE_FILE to a session created with `npm run login`.',
    );
  }
  const password = fs.readFileSync(passwordFile, 'utf8').trim();

  const browser = await chromium.launch({ args: chromiumArgs, proxy: browserProxy() });
  try {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    const page = await context.newPage();
    await loginAsKubeadmin(page, consoleUrl(), password);
    fs.mkdirSync(path.dirname(authStateFile), { recursive: true, mode: 0o700 });
    await context.storageState({ path: authStateFile });
    fs.chmodSync(authStateFile, 0o600);
  } finally {
    await browser.close();
  }
}
