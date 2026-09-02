import { z } from "zod";
import { EnvironmentSchema } from "./environment.js";

// Checklist 1.7.6a — a house RP-facing error shape, deliberately generic:
// `error` is a machine-parseable code, `message` the human sentence. This
// is the base every `verification` error body can extend with its own
// per-error extras (keyEnvironment/passportEnvironment below, for
// example) without ever losing the two fields a caller can always rely
// on. Scope decided directly with the user for this item: ship this base
// now and wire it into EnvironmentMismatchError only — backfilling
// verification's other existing bare-code responses onto this base is
// separate, future work, not folded into this item.
export const ApiErrorSchema = z.object({
  error: z.string(),
  message: z.string(),
});

export type ApiError = z.infer<typeof ApiErrorSchema>;

// 1.7.6/1.7.6a — verification's environment-mismatch rejection. Both
// mismatch directions get their own body (keyEnvironment/passportEnvironment
// name which side actually mismatched), since "mismatch" alone hides which
// side is wrong and the fix differs each way. Copy specimen for both
// directions: console/design/pass-2-switch-to-live.dc.html §07 — reused
// verbatim at the call site, not redrafted. Still a rejected call, not a
// signed VerifyDecision: a signed deny would falsely tell the RP that
// Fence evaluated the passport, when the call was rejected before any of
// that ran.
export const EnvironmentMismatchErrorSchema = ApiErrorSchema.extend({
  error: z.literal("environment_mismatch"),
  keyEnvironment: EnvironmentSchema,
  passportEnvironment: EnvironmentSchema,
});

export type EnvironmentMismatchErrorBody = z.infer<typeof EnvironmentMismatchErrorSchema>;
