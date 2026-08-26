import { AgentSigningError } from "./agent-signing-error.js";

// Shared by ed25519Signer() and signAction() — both need the identical
// fail-closed check before handing a caller-supplied CryptoKey to
// crypto.subtle.sign(), rather than each carrying its own copy that could
// drift.
export function assertEd25519SigningKey(signingKey: CryptoKey): void {
  if (signingKey.algorithm.name !== "Ed25519") {
    throw new AgentSigningError("agent-signing: signing key must be Ed25519");
  }
}
