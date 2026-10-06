import { execFileSync } from 'node:child_process';

/** Run `oc` with an argument vector (no shell) and return trimmed stdout. Uses $KUBECONFIG. */
export function oc(...args: string[]): string {
  return execFileSync('oc', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

/** `oc get <resource> -o json`, parsed. */
export function ocGetJson<T = any>(...args: string[]): T {
  return JSON.parse(oc('get', ...args, '-o', 'json')) as T;
}
