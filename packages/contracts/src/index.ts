export type { AssuranceLevel } from "./assurance-level.js";
export { AssuranceLevelCopy, AssuranceLevelSchema } from "./assurance-level.js";
export type { ApiError, EnvironmentMismatchErrorBody } from "./error.js";
export { ApiErrorSchema, EnvironmentMismatchErrorSchema } from "./error.js";
export { Gate2ConsentCopy } from "./gate2-consent.js";
export type { Environment } from "./environment.js";
export { EnvironmentSchema } from "./environment.js";
export {
  mandateFixture,
  passportFixture,
  statusListCredentialFixture,
  verifyDecisionFixture,
  verifyRequestFixture,
} from "./fixtures.js";
export type { Mandate } from "./mandate.js";
export { MandateSchema } from "./mandate.js";
export type { Passport } from "./passport.js";
export { PassportSchema } from "./passport.js";
export type { BitstringStatusListCredential } from "./status-list.js";
export { BitstringStatusListCredentialSchema, canonicalizeStatusList } from "./status-list.js";
export type { VerifyDecision } from "./verify-decision.js";
export { VerifyDecisionModeSchema, VerifyDecisionOutcomeSchema, VerifyDecisionSchema } from "./verify-decision.js";
export type { Action, VerifyRequest } from "./verify-request.js";
export { canonicalizeAction, VerifyRequestSchema } from "./verify-request.js";
