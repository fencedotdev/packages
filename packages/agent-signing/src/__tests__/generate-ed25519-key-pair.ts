import type { webcrypto } from "node:crypto";

// Test-only helper, not part of the published package (lives under
// __tests__/, excluded from both the vitest run — it has no .test.ts
// suffix — and the coverage glob). Node's own webcrypto.SubtleCrypto
// typings have no overload of generateKey() specific to Ed25519 (only
// RSA/EC/AES/HMAC/PBKDF2/KMAC params narrow the return type), so a plain
// `{ name: "Ed25519" }` call falls through to the generic
// `webcrypto.CryptoKeyPair | CryptoKey` overload — narrowed back to webcrypto.CryptoKeyPair
// here via a genuine `in` structural check, not a type assertion (banned
// by this repo's lint config).
export interface GeneratedEd25519KeyPair {
  readonly privateKey: CryptoKey;
  readonly publicKey: CryptoKey;
  readonly privateKeyJwk: webcrypto.JsonWebKey;
}

function isWebCryptoKeyPair(key: CryptoKey | webcrypto.CryptoKeyPair): key is webcrypto.CryptoKeyPair {
  return "privateKey" in key;
}

export async function generateEd25519KeyPair(): Promise<GeneratedEd25519KeyPair> {
  const generated = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
  if (!isWebCryptoKeyPair(generated)) {
    throw new Error("expected an asymmetric webcrypto.CryptoKeyPair from generateKey('Ed25519', ...)");
  }
  const privateKeyJwk = await crypto.subtle.exportKey("jwk", generated.privateKey);
  return { privateKey: generated.privateKey, publicKey: generated.publicKey, privateKeyJwk };
}
