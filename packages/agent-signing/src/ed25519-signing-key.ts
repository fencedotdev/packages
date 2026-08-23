import type { webcrypto } from "node:crypto";
import { AgentSigningError } from "./agent-signing-error.js";

// This package is Ed25519-only, dispatched from the key's own kty/crv with
// a type-narrowing guard — no other algorithm is supported, and this
// function fails closed on anything else rather than attempting a
// best-effort import. The agent's own runtime generates its keypair and
// only ever hands this function the private half (identity-kyb's own
// register-agent.ts takes the matching publicKeyJwk at registration —
// Fence never holds or generates this key).
//
// Imported as non-extractable: once WebCrypto has this key, the raw `d`
// value can never be read back out of it again by this process, even by
// this package's own later code — deliberately narrower than WebCrypto
// requires, to shrink accidental key-serialization surface (the caller's
// own JsonWebKey object is a separate, ordinary reference the caller is
// responsible for discarding).
export async function importAgentSigningKey(jwk: webcrypto.JsonWebKey): Promise<CryptoKey> {
  if (jwk.kty !== "OKP" || jwk.crv !== "Ed25519") {
    throw new AgentSigningError("agent-signing: unsupported key type — only an Ed25519 (OKP/Ed25519) private-key JWK is accepted");
  }

  try {
    return await crypto.subtle.importKey("jwk", jwk, { name: "Ed25519" }, false, ["sign"]);
  } catch {
    throw new AgentSigningError("agent-signing: failed to import the signing key");
  }
}
