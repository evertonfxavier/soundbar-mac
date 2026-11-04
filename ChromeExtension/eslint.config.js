import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import { defineConfig, globalIgnores } from 'eslint/config';

// A glob for any import that reaches into a layer folder.
const layer = (...names) => names.flatMap((name) => [`**/${name}`, `**/${name}/**`]);

/**
 * The dependency rule of Clean Architecture: a layer imports only from the ones inside it.
 *   domain → (nothing)   infra → domain   main → everything
 */
const dependencyRule = (files, forbidden) => ({
  files,
  rules: {
    'no-restricted-imports': [
      'error',
      {
        patterns: [
          {
            group: layer(...forbidden),
            message: `This layer must not depend on ${forbidden.join(', ')} (see "Architecture" in the README).`,
          },
        ],
      },
    ],
  },
});

/** What only a browser (or the extension runtime) provides: the domain must not touch any of it. */
const PLATFORM_GLOBALS = [
  'chrome',
  'window',
  'document',
  'navigator',
  'WebSocket',
  'localStorage',
  'sessionStorage',
  'MutationObserver',
].map((name) => ({
  name,
  message: 'The domain is plain TypeScript: reach the platform through a port (src/domain/ports.ts).',
}));

export default defineConfig([
  globalIgnores(['dist', 'coverage', 'node_modules']),

  {
    files: ['**/*.ts'],
    extends: [js.configs.recommended, tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
      globals: { ...globals.browser, chrome: 'readonly' },
    },
    rules: {
      eqeqeq: ['error', 'always'],
      'no-console': ['error', { allow: ['warn', 'error'] }],
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
    },
  },

  dependencyRule(['src/domain/**'], ['infra', 'main']),
  dependencyRule(['src/infra/**'], ['main']),
  {
    files: ['src/domain/**'],
    rules: { 'no-restricted-globals': ['error', ...PLATFORM_GLOBALS] },
  },

  {
    // Specs build fakes of browser objects: the casts and the untyped fixtures are the point.
    files: ['tests/**/*.ts'],
    languageOptions: { globals: { ...globals.node } },
    rules: {
      '@typescript-eslint/unbound-method': 'off',
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
      '@typescript-eslint/no-unsafe-return': 'off',
    },
  },

  {
    // Node scripts and config files: plain JavaScript, no type information.
    files: ['**/*.{js,mjs}'],
    extends: [js.configs.recommended, tseslint.configs.disableTypeChecked],
    languageOptions: { globals: { ...globals.node } },
  },
]);
