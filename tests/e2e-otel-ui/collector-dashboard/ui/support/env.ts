import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

/**
 * Directory for reports and traces. OpenShift CI collects $ARTIFACT_DIR; locally everything lands in
 * ./artifacts (git-ignored).
 */
export const artifactDir = process.env.ARTIFACT_DIR ?? path.resolve(__dirname, '..', 'artifacts');

/** True in OpenShift CI step pods (CI=true), where Chromium runs as an arbitrary non-root user. */
export const inCI = !!process.env.CI;

/** Console URL: $BASE_URL, otherwise the console of the cluster in $KUBECONFIG. */
export function consoleUrl(): string {
  const fromEnv = process.env.BASE_URL?.trim();
  const url = fromEnv || execFileSync('oc', ['whoami', '--show-console'], { encoding: 'utf8' }).trim();
  return url.replace(/\/+$/, '');
}

/** Namespace holding the collectors, created by the Chainsaw test and passed in as $OTEL_UI_NAMESPACE. */
export function testNamespace(): string {
  const ns = process.env.OTEL_UI_NAMESPACE;
  if (!ns) {
    throw new Error(
      'OTEL_UI_NAMESPACE is not set. The specs run from the Chainsaw test ' +
        '(tests/e2e-otel-ui/collector-dashboard) which exports the namespace of the collectors.',
    );
  }
  return ns;
}

/**
 * Session cookies of a logged-in console user. Either provided via $AUTH_STATE_FILE (see
 * `npm run login`) or created by global-setup from the kubeadmin password.
 */
export const authStateFile =
  process.env.AUTH_STATE_FILE ?? path.join(os.tmpdir(), 'otel-ui-auth', 'state.json');

/** File with the kubeadmin password: $KUBEADMIN_PASSWORD_FILE, else ${SHARED_DIR}/kubeadmin-password. */
export function kubeadminPasswordFile(): string | undefined {
  const candidates = [
    process.env.KUBEADMIN_PASSWORD_FILE,
    process.env.SHARED_DIR ? path.join(process.env.SHARED_DIR, 'kubeadmin-password') : undefined,
  ];
  return candidates.find((file): file is string => !!file && fs.existsSync(file));
}

/**
 * Chromium flags needed when running in a container as an arbitrary UID: no user namespaces for the sandbox,
 * a small /dev/shm, and no GPU. Same flags as the Cypress suite of distributed-tracing-console-plugin.
 */
export const chromiumArgs = inCI ? ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] : [];

/**
 * Proxy for the browser. OpenShift CI steps for clusters that are only reachable through a proxy source
 * ${SHARED_DIR}/proxy-conf.sh, which sets http(s)_proxy and no_proxy. Cypress picks these up by itself,
 * Playwright's Chromium does not, and it wants the credentials of the proxy as separate options.
 */
export function browserProxy(): { server: string; bypass?: string; username?: string; password?: string } | undefined {
  const value =
    process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy;
  if (!value) {
    return undefined;
  }
  const url = new URL(value);
  return {
    server: `${url.protocol}//${url.host}`,
    bypass: process.env.NO_PROXY || process.env.no_proxy || undefined,
    username: url.username ? decodeURIComponent(url.username) : undefined,
    password: url.password ? decodeURIComponent(url.password) : undefined,
  };
}
