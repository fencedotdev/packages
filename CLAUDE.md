# Fence — packages

Public, versioned packages Fence publishes for third-party consumption — renamed from `contracts` 2026-08-21 (npm-workspaces monorepo, one package per `packages/*/`) when this became a home for more than the original contract schemas.

Full product brief: `../internal/briefs/260727_fence_id_v1.0.md`
Build order: `../internal/checklists/fence-build-order.md`
How we work (stack + process): `../internal/onboarding/fence-team-brief-how-we-work.md`

## Non-negotiable rules

**No `Co-Authored-By: Claude` or any AI attribution in commits or PRs.** Never add `Co-Authored-By:`, "Generated with Claude Code", or any AI tool attribution to a commit message or PR description.

**No payment fields.** Nothing in this repo — any package's schema or API shape — may introduce a payment-shaped field (amounts tied to settlement, card/wallet references, anything beyond the generic `limits`/`value` shapes already in `contracts`' M·2/M·3) unless the brief's Prong 2 is explicitly and separately scoped. See `fence-build-order.md`, Critical architecture notes.

---

## packages specifics

**Type:** npm workspaces monorepo, no deploy — publishes one or more versioned public packages every consuming repo (and, for some packages, third parties) imports.

**Stack:** TypeScript. Each package's own dependencies vary — `contracts` is pure Zod with zero runtime I/O; a package like `credential-verification` needs `jose` and network JWKS fetches. No framework, no database, no HTTP server anywhere in this repo.

**Why public — and why this is deliberately a separate repo from `internal-packages` (private):** the split is by audience, not by "is this shared code." A package belongs here only if a third party has a real reason to see or depend on it — the interoperability contract itself (`contracts`), or verification logic a relying party might want to audit rather than trust as a black box (`credential-verification`). Purely internal plumbing (e.g. the Supabase console-session JWT check used only by Fence's own three backend services) belongs in `internal-packages` instead — see that repo's own CLAUDE.md. This distinction was made explicit 2026-08-21 after this repo's public status (the only public repo in the org) was flagged as a real, actively-managed risk boundary in `fence-build-order.md` v1.24 — kept off the shared self-hosted CI runner pool specifically because of it. Check before adding a new package here: does a third party genuinely need to see this, or is it internal?

**Structure:**
```
packages/
  contracts/              # @fence.dev/contracts — the four M·1–M·4 shapes
                          # from the brief: passport (SD-JWT-VC payload),
                          # mandate, verify() request, verify() decision.
                          # This is the seam every other repo builds
                          # against (App. C).
  credential-verification/ # @fence.dev/credential-verification — did:web
                          # passport-signature verification + offline
                          # revocation-status checking, ported from
                          # verification's own internal copy (2026-08-21).
                          # No consumer-verification gate yet (no merged
                          # consuming repo yet) — see its own package.json.
tsconfig.base.json         # shared compiler options every package's own
                          # tsconfig.json extends
eslint.config.mjs          # shared lint config, globs across packages/*/src
vitest.config.ts           # shared test config, same glob
```

**Does not own:** any business logic, any persistence, any HTTP handling — those all live in the consuming repos.

**Publishing**: the public npm registry (`registry.npmjs.org`), via npm's Trusted Publisher/OIDC flow — no stored `NPM_TOKEN`. See `.github/workflows/ci.yml`'s own header comments for the full mechanism and for `contracts`' consumer-verification gate (0.5.6). `credential-verification` uses a simpler, ungated publish path (its own job, `publish-credential-verification`) — add the same consumer-verification gate once it has a real downstream consumer with its own contract test, don't leave it ungated out of inertia. Every new package's very first version must be published manually (an authenticated human `npm publish`, with 2FA) before npm's Trusted Publisher flow can take over for later versions — Trusted Publisher can only be configured against a package that already exists on the registry (`contracts`' own 0.3.7 history, repeated for `credential-verification`'s v0.1.0).

**Architecture invariants (per `contracts` specifically):**
- No field anywhere in `contracts` may be payment-shaped (no `funded`, no `payment` action type, no card/wallet reference) until Prong 2 is explicitly and separately scoped. Enforced by `packages/contracts/src/__tests__/no-payment-fields.test.ts`, not just this instruction.
- `mandate.constraints.limits` is generic (`{ metric, unit, max }`) — a spend cap and an API quota are the same shape with different `metric` values. Never add a payment-specific limit type.
- The mandate is *referenced* from the passport (`mandateRef`), never embedded — see M·1's design note.
- `decision.outcome` (the honest verdict) and `decision.effective` (was it enforced) are separate fields — this is the enforcement-mode seam `grace` slots into later without a schema change.
- A version bump to `contracts` must pass the consumer-driven contract test suite against every consuming repo before it publishes (see `fence-checklist-phase-0.md` 0.3.7, 0.5.6).

**Architecture invariants (per `credential-verification` specifically):**
- Fails closed on every failure mode (network error, malformed document, wrong key, tampered payload, wrong algorithm) — never throws, always resolves to `false`/`unavailable`. Preserve this discipline; a relying party depending on this package for an audit trail needs one honest caller-visible signal, not a mix of thrown errors and boolean returns.
- `live`/`test` resolve to genuinely different did:web hosts (`fence.dev` / `sandbox.fence.dev`), never the same document with a different key selected — always take the environment as an explicit caller argument, never infer it from a token's own self-asserted `iss`/`issuer` claim (that claim is still cross-checked, just never trusted as the source of truth for which host to resolve).
- `checkOfflineRevocationStatus`'s 500ms per-fetch timeout is deliberate — matched to Fence's own verify() hot-path latency budget, the one real caller this was tuned for. Don't loosen it for test convenience; a caller wanting a longer budget wraps this function in its own retry/timeout logic instead (see the cross-repo test's own retry loop for the pattern).

**Domain vocabulary:** passport, mandate, `verify()`, claims, assurance level, outcome/effective, reason codes, environment (`live`/`test`).

---

## Type safety rules

```
No any
No type assertions (as SomeType) — fix the type instead
No non-null assertions (value!) — handle the nullable case
No @ts-ignore
No @ts-expect-error without a comment explaining why the type system is wrong
```

TypeScript strict mode is enabled. All compiler errors are resolved — not silenced.

## Testing (TDD — non-negotiable)

1. Write failing test → confirm RED
2. Write minimum code to pass → confirm GREEN
3. Refactor → commit

Writing implementation before the test is not acceptable. 100% test coverage is mandatory and enforced in CI — a thin package is not an excuse for thin tests; in a repo this small, most of what exists *is* the product.

## Complexity limits (ESLint-enforced)

- Max file length: 400 lines (excluding blanks and comments)
- Max function length: 60 lines
- Max cyclomatic complexity per function: 12
- Max indentation depth: 3

When you hit a limit, decompose — do not raise the limit.

Banned folder names: `utils/`, `helpers/`, `common/`, `shared/`, `core/` — everything gets a domain-specific home.

## Security

- `eslint-plugin-security` in CI — all issues resolved before merge
- `npm audit --audit-level=high` in CI — failing audit blocks merge
- **Socket.dev** GitHub App installed — scans every PR touching `package.json`/`package-lock.json` for malicious packages, hidden telemetry, supply-chain attacks, and new maintainers added to dependencies
- Branch protection on `main`: no direct pushes, PR required, CI must pass
- Signed commits required
- **A sandbox-blocked action is a stop signal, not an obstacle.** If a git operation, tool call, or permission check is blocked, stop and report back exactly what was blocked — never reach for a different tool or mechanism (the GitHub API in place of `git`, a raw script in place of a blocked command, manually constructing commits/blobs/trees, etc.) to reproduce the same effective action a different way. The restriction exists for a reason even when it isn't obvious from where you're standing, and routing around it defeats whatever it was protecting regardless of how legitimate the underlying task is — this applies with extra force to anything touching signed commits, branch protection, or another repo's checkout.
- No credentials in source code — GitHub secret scanning + push protection enabled; a `git-secrets` pre-commit hook blocks known secret patterns before they leave your machine
- This repo is permanently excluded from the shared self-hosted CI runner pool (`fence-build-order.md` v1.24) — it's the only public repo in the org, and that pool is shared with the KMS-signing-key and DB-credential-holding repos.
- If this repo ever touches the issuer signing key or IDV vendor credentials directly, stop — it almost certainly shouldn't. Signing happens only in `issuance`; KYB/KYC vendor calls happen only in `identity-kyb`. See `fence-team-brief-how-we-work.md` §8.

## Hooks

An automatic code review runs after every Claude Code session in this repo. It reviews modified files against `.claude/automatic-code-review/rules.md` and reports convention violations before you see the result — including the no-payment-fields rule above where a package here touches `contracts` or `verify()` shapes. Do not bypass the reviewer.

The `PreToolUse` hook blocks `--no-verify`, `--force`, and `--hard` on git commands.

## MCP-first for third-party integrations

Before hand-rolling a client for a vendor, check whether they publish an MCP server. Supabase is already connected in this workspace — use it for schema/migration/log work rather than raw `psql` or dashboard clicks. See `fence-team-brief-how-we-work.md` §7 for what's connected and what isn't.
