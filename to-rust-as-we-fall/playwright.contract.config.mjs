import { defineConfig } from '@playwright/test';

// Pure policy/input-boundary contract. It deliberately has no webServer and
// does not consume build/web, so a stale export cannot make this probe green.
export default defineConfig({
  testDir: './tests/web',
  testMatch: 'basin-fill-proof.spec.mjs',
  grep: /Web persona trace refusal and input-ledger contract vectors/,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30_000,
  outputDir: process.env.TRAWF_PLAYWRIGHT_OUTPUT_DIR
    ?? '../.test-gate/playwright-persona-contract',
  reporter: [['list']],
});
