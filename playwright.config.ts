import { defineConfig } from '@playwright/test';

// The product is native macOS. Playwright exercises the real CLI engine;
// XCTest captures native UI screenshots (npm run test:ui).
export default defineConfig({
  testDir: './Tests/Integration',
  outputDir: 'test-results',
  globalSetup: './Tests/Integration/setup.ts',
  timeout: 120_000,
  workers: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: { screenshot: 'only-on-failure' },
  projects: [{ name: 'native-engine' }],
});
