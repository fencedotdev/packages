import { describe, expect, it } from "vitest";
import { AgentSigningError } from "../agent-signing-error.js";
import { importAgentSigningKey } from "../ed25519-signing-key.js";
import { generateEd25519KeyPair } from "./generate-ed25519-key-pair.js";

describe("importAgentSigningKey", () => {
  it("imports a genuine Ed25519 (OKP/Ed25519) private-key JWK into a non-extractable CryptoKey", async () => {
    const { privateKeyJwk } = await generateEd25519KeyPair();

    const key = await importAgentSigningKey(privateKeyJwk);

    expect(key.algorithm.name).toBe("Ed25519");
    expect(key.usages).toEqual(["sign"]);
    expect(key.extractable).toBe(false);
  });

  it("fails closed on a non-Ed25519 kty, without echoing the JWK", async () => {
    const jwk = { kty: "RSA", n: "not-actually-ed25519", e: "AQAB" };

    await expect(importAgentSigningKey(jwk)).rejects.toThrow(AgentSigningError);
    await expect(importAgentSigningKey(jwk)).rejects.not.toThrow(/not-actually-ed25519/);
  });

  it("fails closed on an OKP key with a non-Ed25519 curve", async () => {
    const jwk = { kty: "OKP", crv: "X25519", x: "irrelevant" };

    await expect(importAgentSigningKey(jwk)).rejects.toThrow(AgentSigningError);
  });

  it("fails closed on a malformed Ed25519-labelled JWK that WebCrypto itself rejects", async () => {
    const jwk = { kty: "OKP", crv: "Ed25519", d: "not-valid-base64url-key-material" };

    await expect(importAgentSigningKey(jwk)).rejects.toThrow(AgentSigningError);
  });
});
