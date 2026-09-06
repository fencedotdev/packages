import js from "@eslint/js";
import tseslint from "typescript-eslint";
import security from "eslint-plugin-security";

export default tseslint.config(
  {
    ignores: ["**/dist/**", "node_modules/**", "coverage/**", ".claude/worktrees/**"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  security.configs.recommended,
  {
    // Type-aware rules only apply where a package's own tsconfig.json
    // "include" reaches (packages/*/src/**/*.ts) — root-level config files
    // like this one aren't part of any package's TS project and can't be
    // type-checked, so they stay on the non-type-checked block above.
    files: ["packages/*/src/**/*.ts"],
    extends: [...tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-non-null-assertion": "error",
      "@typescript-eslint/consistent-type-assertions": ["error", { assertionStyle: "never" }],
      "@typescript-eslint/ban-ts-comment": [
        "error",
        {
          "ts-expect-error": "allow-with-description",
          "ts-ignore": true,
          "ts-nocheck": true,
          "ts-check": false,
        },
      ],

      "max-lines": ["error", { max: 400, skipBlankLines: true, skipComments: true }],
      "max-lines-per-function": ["error", { max: 60, skipBlankLines: true, skipComments: true }],
      complexity: ["error", 12],
      "max-depth": ["error", 3],

      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["*/utils", "*/utils/*", "*/helpers", "*/helpers/*", "*/common", "*/common/*", "*/shared", "*/shared/*", "*/core", "*/core/*"],
              message: "Banned folder name (see CLAUDE.md) — give this a domain-specific home instead of a grab-bag module.",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["packages/*/src/__tests__/**/*.ts", "**/*.test.ts"],
    rules: {
      "max-lines-per-function": "off",
      "@typescript-eslint/no-explicit-any": "off",
    },
  },
);
