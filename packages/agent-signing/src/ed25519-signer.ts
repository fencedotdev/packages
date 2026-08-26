import type { Signer } from "http-message-sig";
import { AgentSigningError } from "./agent-signing-error.js";
import { assertEd25519SigningKey } from "./ed25519-signing-key-guard.js";

// Wraps a WebCrypto Ed25519 CryptoKey as http-message-sig's own Signer
// shape. Re-checked here (not just at import time) since a caller can
// construct signAgentRequest's options directly with any CryptoKey —
// fails closed rather than letting a wrong-algorithm key silently produce
// a signature no verifier will accept as ed25519.
export function ed25519Signer(privateKey: CryptoKey, keyId: string): Signer {
  assertEd25519SigningKey(privateKey);

  return {
    keyid: keyId,
    alg: "ed25519",
    async sign(data: string): Promise<Uint8Array> {
      try {
        const signature = await crypto.subtle.sign("Ed25519", privateKey, new TextEncoder().encode(data));
        return new Uint8Array(signature);
      } catch {
        throw new AgentSigningError("agent-signing: signing failed");
      }
    },
  };
}
