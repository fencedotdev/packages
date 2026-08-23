import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// Same regression class credential-verification's own packaging.test.ts
// guards against (2026-08-22): this package's "type": "module" means
// Node's real ESM resolver requires an explicit .js extension on every
// relative import in the compiled dist/ output, even though TypeScript's
// Bundler moduleResolution accepts an extensionless specifier at
// typecheck time. Source-level unit tests never exercise the compiled
// output under Node's real resolver, so this can pass every other check
// and still break for a genuinely fresh `npm install`.
const distDir = fileURLToPath(new URL("../../dist", import.meta.url));

describe("the published dist/ build", () => {
  it.each(["index.js", "ed25519-signing-key.js", "ed25519-signer.js", "sign-agent-request.js"])( // gitleaks:allow -- literal built-file names (hex-ish "ed25519" trips entropy heuristics), not a secret
    "%s's relative imports all carry an explicit .js extension",
    (file) => {
      // eslint-disable-next-line security/detect-non-literal-fs-filename -- fixed dist dir + one of this test's own four literal filenames, not user input
      const contents = readFileSync(path.join(distDir, file), "utf8");
      const relativeSpecifiers = [...contents.matchAll(/from ["'](\.[^"']+)["']/g)].map((match) => match[1]);
      for (const specifier of relativeSpecifiers) {
        expect(specifier).toMatch(/\.js$/);
      }
    },
  );
});
