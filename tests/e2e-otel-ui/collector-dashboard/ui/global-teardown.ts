import * as fs from 'node:fs';
import { authStateFile } from './support/env';

/**
 * Remove the console session that global-setup created from the kubeadmin password, so that it does not stay in
 * the temp directory of a developer machine. A session that was handed in with $AUTH_STATE_FILE belongs to
 * the caller and is left alone.
 */
export default async function globalTeardown(): Promise<void> {
  if (!process.env.AUTH_STATE_FILE) {
    fs.rmSync(authStateFile, { force: true });
  }
}
