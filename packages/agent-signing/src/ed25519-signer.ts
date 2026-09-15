import type { Signer } from "http-message-sig";
import { AgentSigningError } from "./agent-signing-error.js";
import { assertEd25519SigningKey } from "./ed25519-signing-key-guard.js";

// Wraps a WebCrypto Ed25519 CryptoKey as http-message-sig's own Signer
// shape. Re-checked here (not just at import time) since a caller can
// construct signAgentRequest's options directly with any CryptoKey —
// fails closed rather than letting a wrong-algorithm key silently produce
// a signature no verifier will accept as ed25519.
//
// Migrated for http-message-sig 0.2.0 -> 0.3.0: the Signer shape dropped
// `keyid`/`alg` entirely (those are now caller-supplied `parameters` on
// createSignature() itself, see sign-agent-request.ts) and renamed `alg`
// to `algorithm`; `sign()` now takes the already-encoded Uint8Array
// signature base directly rather than a raw string, so this module no
// longer owns the TextEncoder step.
export function ed25519Signer(privateKey: CryptoKey): Signer {
  assertEd25519SigningKey(privateKey);

  return {
    algorithm: "ed25519",
    async sign(data: Uint8Array): Promise<Uint8Array> {
      try {
        // http-message-sig's Signer.sign() types `data` as
        // Uint8Array<ArrayBufferLike> (which includes SharedArrayBuffer),
        // narrower than WebCrypto's own BufferSource — copied into a fresh
        // Uint8Array<ArrayBuffer> here rather than asserted, since a real
        // SharedArrayBuffer-backed input would otherwise silently pass a
        // type check it can't actually satisfy at the WebCrypto boundary.
        const dataBytes = new Uint8Array(data);
        const signature = await crypto.subtle.sign("Ed25519", privateKey, dataBytes);
        return new Uint8Array(signature);
      } catch {
        throw new AgentSigningError("agent-signing: signing failed");
      }
    },
  };
}
