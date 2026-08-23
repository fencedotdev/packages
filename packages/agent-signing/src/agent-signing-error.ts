// Every failure mode in this package (bad key type, import failure, signing
// failure, an unexpected error from http-message-sig) is mapped to this one
// error type with a fixed, generic message — never the caller-supplied key
// material or any value derived from it. Mirrors the fail-closed,
// nothing-leaked-in-the-catch-path discipline already established by
// verification's request-signature-verification.ts and issuance's
// kms-signer.ts.
export class AgentSigningError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AgentSigningError";
  }
}
