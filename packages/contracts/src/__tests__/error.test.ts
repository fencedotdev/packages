import { describe, expect, it } from "vitest";
import {
  ApiErrorSchema,
  EnvironmentMismatchErrorSchema,
  type ApiError,
  type EnvironmentMismatchErrorBody,
} from "../error.js";
import {
  ApiErrorSchema as ReexportedApiErrorSchema,
  EnvironmentMismatchErrorSchema as ReexportedEnvironmentMismatchErrorSchema,
} from "../index.js";

// Checklist 1.7.6a — a generic, extensible house error base
// ({error, message}), with EnvironmentMismatchError's own
// keyEnvironment/passportEnvironment as its per-error extras layered on
// top, exactly as scoped by prd-gate for this item (resolved directly by
// the user: ship the generic base now, wire it into
// EnvironmentMismatchError only — verification's other ~12 bare-code
// error responses are separate, future work, not folded in here).
//
// error: "environment_mismatch" (underscore) is the design doc's own
// specimen (console/design/pass-2-switch-to-live.dc.html §07) — this
// package must ship the underscore form; the space-separated
// "environment mismatch" string that was actually in
// verify-request-handler.ts before this item is a regression, not a
// valid alternative, and is asserted rejected below.

describe("ApiErrorSchema", () => {
  const validApiError: ApiError = { error: "some_error_code", message: "Something went wrong, in plain language." };

  it("accepts a minimal generic house error", () => {
    expect(ApiErrorSchema.safeParse(validApiError).success).toBe(true);
  });

  it("rejects an error body missing the plain-language message", () => {
    const { message, ...withoutMessage } = validApiError;
    void message;

    expect(ApiErrorSchema.safeParse(withoutMessage).success).toBe(false);
  });

  it("rejects an error body missing the machine-parseable error code", () => {
    const { error, ...withoutError } = validApiError;
    void error;

    expect(ApiErrorSchema.safeParse(withoutError).success).toBe(false);
  });

  it("rejects a non-string error code", () => {
    expect(ApiErrorSchema.safeParse({ error: 403, message: "Something went wrong." }).success).toBe(false);
  });

  it("rejects a non-string message", () => {
    expect(ApiErrorSchema.safeParse({ error: "some_error_code", message: null }).success).toBe(false);
  });
});

describe("EnvironmentMismatchErrorSchema", () => {
  const directionA: EnvironmentMismatchErrorBody = {
    error: "environment_mismatch",
    keyEnvironment: "test",
    passportEnvironment: "live",
    message:
      "You used a test API key to check a live passport. Fence never checks a passport across environments. Use your live API key, or check a test passport.",
  };

  const directionB: EnvironmentMismatchErrorBody = {
    error: "environment_mismatch",
    keyEnvironment: "live",
    passportEnvironment: "test",
    message:
      "You used a live API key to check a test passport. Test passports only work with test API keys. The company that issued this passport may not have switched to live yet.",
  };

  it("accepts direction A — a test key checking a live passport", () => {
    expect(EnvironmentMismatchErrorSchema.safeParse(directionA).success).toBe(true);
  });

  it("accepts direction B — a live key checking a test passport", () => {
    expect(EnvironmentMismatchErrorSchema.safeParse(directionB).success).toBe(true);
  });

  it("also validates against the generic house base — it's an extension of ApiErrorSchema, not a special case", () => {
    expect(ApiErrorSchema.safeParse(directionA).success).toBe(true);
  });

  it("rejects the pre-1.7.6a space-separated 'environment mismatch' string — the shipped literal is the underscore form", () => {
    const withSpace = { ...directionA, error: "environment mismatch" };

    expect(EnvironmentMismatchErrorSchema.safeParse(withSpace).success).toBe(false);
  });

  it("rejects any error code other than the literal 'environment_mismatch'", () => {
    const wrongCode = { ...directionA, error: "invalid_api_key" };

    expect(EnvironmentMismatchErrorSchema.safeParse(wrongCode).success).toBe(false);
  });

  it("rejects a keyEnvironment outside live/test", () => {
    const invalid = { ...directionA, keyEnvironment: "staging" };

    expect(EnvironmentMismatchErrorSchema.safeParse(invalid).success).toBe(false);
  });

  it("rejects a passportEnvironment outside live/test", () => {
    const invalid = { ...directionA, passportEnvironment: "staging" };

    expect(EnvironmentMismatchErrorSchema.safeParse(invalid).success).toBe(false);
  });

  it("rejects a body missing keyEnvironment", () => {
    const { keyEnvironment, ...withoutKeyEnvironment } = directionA;
    void keyEnvironment;

    expect(EnvironmentMismatchErrorSchema.safeParse(withoutKeyEnvironment).success).toBe(false);
  });

  it("rejects a body missing passportEnvironment", () => {
    const { passportEnvironment, ...withoutPassportEnvironment } = directionA;
    void passportEnvironment;

    expect(EnvironmentMismatchErrorSchema.safeParse(withoutPassportEnvironment).success).toBe(false);
  });

  it("rejects a body missing the plain-language message", () => {
    const { message, ...withoutMessage } = directionA;
    void message;

    expect(EnvironmentMismatchErrorSchema.safeParse(withoutMessage).success).toBe(false);
  });
});

describe("re-exported from index.ts", () => {
  it("exposes ApiErrorSchema as the same schema instance", () => {
    expect(ReexportedApiErrorSchema).toBe(ApiErrorSchema);
  });

  it("exposes EnvironmentMismatchErrorSchema as the same schema instance", () => {
    expect(ReexportedEnvironmentMismatchErrorSchema).toBe(EnvironmentMismatchErrorSchema);
  });
});
