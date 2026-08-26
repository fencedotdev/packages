import { verifyRequestFixture, type Action } from "@fence.dev/contracts";
import { canonicalizeAction } from "@fence.dev/contracts";
import { describe, expect, it } from "vitest";
import { AgentSigningError } from "../agent-signing-error.js";
import { signAction } from "../sign-action.js";
import { generateEd25519KeyPair } from "./generate-ed25519-key-pair.js";

// verification's request-signature-verification.ts (the real consumer of
// this signature) decodes the base64url signature string with
// `Buffer.from(signature, "base64url")` before handing the raw bytes to
// `crypto.subtle.verify`. Mirrored here verbatim rather than assuming a
// specific decode helper, so this test proves interop with that exact
// process, not with whatever this package's own author happened to pick.
function decodeAsVerificationWould(signature: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array(Buffer.from(signature, "base64url"));
}

const actionFixture: Action = verifyRequestFixture.action;

describe("signAction", () => {
  it("round-trips: a signature it produces verifies against the same action via raw crypto.subtle.verify", async () => {
    const { privateKey, publicKey } = await generateEd25519KeyPair();

    const signature = await signAction(actionFixture, privateKey);

    const verified = await crypto.subtle.verify(
      "Ed25519",
      publicKey,
      decodeAsVerificationWould(signature),
      new TextEncoder().encode(canonicalizeAction(actionFixture)),
    );
    expect(verified).toBe(true);
  });

  it("produces a base64url string with no padding characters", async () => {
    const { privateKey } = await generateEd25519KeyPair();

    const signature = await signAction(actionFixture, privateKey);

    expect(signature).not.toContain("=");
    expect(signature).not.toContain("+");
    expect(signature).not.toContain("/");
  });

  it("decodes byte-for-byte the same way verification's real verifyRequestSignature() decodes it, to the expected Ed25519 signature length", async () => {
    const { privateKey } = await generateEd25519KeyPair();

    const signature = await signAction(actionFixture, privateKey);
    const decoded = decodeAsVerificationWould(signature);

    // Raw Ed25519 signatures are always 64 bytes — confirms the decode
    // path produces genuine raw signature bytes, not some other encoding
    // shape (e.g. a DER-wrapped signature) that would also happen to be
    // valid base64url but not verify.
    expect(decoded.length).toBe(64);
  });

  it("fails verification when the destination field is mutated after signing", async () => {
    const { privateKey, publicKey } = await generateEd25519KeyPair();
    const signature = await signAction(actionFixture, privateKey);

    const tampered: Action = { ...actionFixture, destination: "US" };

    const verified = await crypto.subtle.verify(
      "Ed25519",
      publicKey,
      decodeAsVerificationWould(signature),
      new TextEncoder().encode(canonicalizeAction(tampered)),
    );
    expect(verified).toBe(false);
  });

  it("fails closed with AgentSigningError when handed a non-Ed25519 CryptoKey (ECDSA), without leaking key material", async () => {
    const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);

    await expect(signAction(actionFixture, privateKey)).rejects.toThrow(AgentSigningError);
    await expect(signAction(actionFixture, privateKey)).rejects.not.toThrow(/P-256/);
  });

  it("fails closed with AgentSigningError when handed a non-Ed25519 CryptoKey (RSA)", async () => {
    const { privateKey } = await crypto.subtle.generateKey(
      { name: "RSA-PSS", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      false,
      ["sign"],
    );

    await expect(signAction(actionFixture, privateKey)).rejects.toThrow(AgentSigningError);
  });

  it("fails closed with AgentSigningError, not a raw WebCrypto rejection, when the key passes the algorithm check but cannot actually sign", async () => {
    // An Ed25519 public key: algorithm.name is "Ed25519" (passes the
    // type-narrowing guard), but crypto.subtle.sign() itself rejects it —
    // this is the one realistic signing-failure mode distinct from
    // wrong-key-type available in this environment (WebCrypto's Ed25519
    // signing has no other documented failure path once the algorithm
    // check has passed), so it's exercised here rather than a fabricated
    // untestable branch.
    const { publicKey } = await generateEd25519KeyPair();

    await expect(signAction(actionFixture, publicKey)).rejects.toThrow(AgentSigningError);
  });
});
