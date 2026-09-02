import { z } from "zod";
import { describe, expect, it } from "vitest";
import { ApiErrorSchema, EnvironmentMismatchErrorSchema } from "../error.js";
import { MandateSchema } from "../mandate.js";
import { PassportSchema } from "../passport.js";
import { BitstringStatusListCredentialSchema } from "../status-list.js";
import { VerifyDecisionSchema } from "../verify-decision.js";
import { VerifyRequestSchema } from "../verify-request.js";

// 0.5.5 — this test IS the enforcement mechanism for the no-payment-fields
// rule (fence-build-order.md, Critical architecture notes), not just
// documentation of it. No field anywhere in this package may be
// payment-shaped — amounts tied to settlement, card/wallet references,
// anything beyond the generic limits/value shapes already in M·2/M·3 —
// until the brief's Prong 2 is explicitly and separately scoped.
//
// 1.7.6a adds ApiErrorSchema/EnvironmentMismatchErrorSchema to this same
// enforcement list, per that item's own prd-gate recommendation — every
// contract shape in this package gets this coverage, not just the
// original four/five.

const BANNED_FIELD_NAMES = [
  "funded",
  "payment",
  "settlement",
  "card",
  "cardNumber",
  "wallet",
  "walletAddress",
  "paymentMethod",
  "chargeId",
  "iban",
];

// Walks the JSON Schema representation structurally, narrowing via typeof
// only — no type assertions, matching this repo's type-safety rules.
function getProperty(node: unknown, key: string): unknown {
  if (typeof node !== "object" || node === null) return undefined;

  for (const [candidateKey, value] of Object.entries(node)) {
    if (candidateKey === key) return value;
  }
  return undefined;
}

function collectFieldNames(node: unknown, names: Set<string>): void {
  const properties = getProperty(node, "properties");
  if (typeof properties === "object" && properties !== null) {
    for (const [propName, propSchema] of Object.entries(properties)) {
      names.add(propName);
      collectFieldNames(propSchema, names);
    }
  }

  const items = getProperty(node, "items");
  if (items !== undefined) {
    collectFieldNames(items, names);
  }
}

const ALL_SCHEMAS = {
  passport: PassportSchema,
  mandate: MandateSchema,
  verifyRequest: VerifyRequestSchema,
  verifyDecision: VerifyDecisionSchema,
  statusListCredential: BitstringStatusListCredentialSchema,
  apiError: ApiErrorSchema,
  environmentMismatchError: EnvironmentMismatchErrorSchema,
} as const;

describe("no payment-shaped fields exist anywhere in this package's contract shapes", () => {
  it.each(Object.entries(ALL_SCHEMAS))("%s has no banned field name", (_name, schema) => {
    const fieldNames = new Set<string>();
    collectFieldNames(z.toJSONSchema(schema), fieldNames);

    for (const banned of BANNED_FIELD_NAMES) {
      expect(fieldNames.has(banned)).toBe(false);
    }
  });

  it("verify-request's action.type stays a free string, not a closed enum — so a future 'payment' action type never needs a schema migration", () => {
    const jsonSchema = z.toJSONSchema(VerifyRequestSchema);
    const action = getProperty(getProperty(jsonSchema, "properties"), "action");
    const actionType = getProperty(getProperty(action, "properties"), "type");

    expect(getProperty(actionType, "type")).toBe("string");
    expect(getProperty(actionType, "enum")).toBeUndefined();
  });
});
