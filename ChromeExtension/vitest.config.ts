import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.spec.ts'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      include: ['src/**'],
      // The three entry points only hand the real browser objects to `start*` (tested in tests/main);
      // building them is checked by tests/build.
      exclude: ['src/main/background.ts', 'src/main/inject.ts', 'src/main/relay.ts'],
      reporter: ['text-summary', 'text'],
      // The rules and the adapters are what the tests are for: a drop here means logic nothing checks.
      thresholds: {
        'src/domain/**': { statements: 95, branches: 90, functions: 95, lines: 95 },
        'src/infra/**': { statements: 90, branches: 80, functions: 90, lines: 90 },
        'src/main/**': { statements: 90, branches: 80, functions: 90, lines: 90 },
      },
    },
  },
});
