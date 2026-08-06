import { defineConfig } from '@playwright/test';

const port = Number(process.env.TRAWF_WEB_PORT ?? '41739');
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: './tests/web',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  // A real Basin clear waits for three physical bodies at both group staging
  // lines and traverses the authored water cadence. On the Web runner that
  // reached its final visible interaction at ~184 s, so 180 s could cancel the
  // click before Godot received it and falsely report a gameplay failure.
  timeout: 240_000,
  outputDir: process.env.TRAWF_PLAYWRIGHT_OUTPUT_DIR ?? '../.test-gate/playwright',
  expect: { timeout: 15_000 },
  reporter: [
    ['list'],
    ['./tests/web/persona-validation-reporter.mjs'],
  ],
  use: {
    baseURL,
    headless: true,
    viewport: { width: 1280, height: 720 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node tests/web/serve-web-export.mjs',
    url: `${baseURL}/index.html`,
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
