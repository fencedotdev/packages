import { httpbis, type VerifyingKey } from "http-message-signatures";
import { describe, expect, it } from "vitest";
import { importAgentSigningKey } from "../ed25519-signing-key.js";
import { signAgentRequest } from "../sign-agent-request.js";
import { generateEd25519KeyPair } from "./generate-ed25519-key-pair.js";

// The point of this file: round-trip self-verification (this package
// signing, then this package or http-message-sig itself claiming the
// signature is valid) proves nothing about real interop — it would pass
// even if both sides shared the same bug. This cross-verifies every
// signature this package produces against dhensby's independent
// http-message-signatures implementation (evaluated 2026-08-13, passed
// over for production use but not for quality — vendored here test-only
// specifically for this purpose), a genuinely separate RFC 9421
// implementation that didn't produce the signature it's checking.

// dhensby's Verifier shape: (data, signature, parameters) => Promise<boolean | null>.
// Implemented via the same WebCrypto primitive this package's own signer
// uses to produce the signature — but independently invoked by dhensby's
// own signature-base construction and parameter parsing, not this
// package's, which is exactly what makes this a real interop check.
// Buffer is re-copied into a plain Uint8Array before handing it to
// subtle.verify — Buffer's generic backing type (ArrayBufferLike) doesn't
// structurally satisfy WebCrypto's stricter BufferSource typing.
function independentEd25519Verifier(publicKey: CryptoKey): VerifyingKey {
  return {
    algs: ["ed25519"],
    async verify(data: Buffer, signature: Buffer): Promise<boolean> {
      return crypto.subtle.verify("Ed25519", publicKey, new Uint8Array(signature), new Uint8Array(data));
    },
  };
}

function toHeaderRecord(request: { headers: Record<string, string> }): Record<string, string> {
  return request.headers;
}

describe("web-bot-auth interop — independent-verifier cross-check", () => {
  it("produces a signature dhensby's http-message-signatures independently verifies as valid", async () => {
    const { privateKey, publicKey, privateKeyJwk } = await generateEd25519KeyPair();
    const signingKey = await importAgentSigningKey(privateKeyJwk);
    const request = { method: "GET", url: "https://rp.example.com/orders/42", headers: {} };

    // Deliberately real wall-clock time, not a fixed historical date: this
    // package's own signature-expiry field is checked by dhensby's
    // verifier against real Date.now() with no way to inject a fake "now"
    // (confirmed against its source — expiry is `now > expires`,
    // unconditionally real-time), so a hardcoded date would drift into
    // "always expired" the moment the calendar passes it. Same class of
    // bug as this project's own prior hardcoded-test-date lesson.
    const signatureHeaders = await signAgentRequest(request, {
      signingKey,
      keyId: "agent-key-1",
      signatureAgent: "https://11111111-1111-1111-1111-111111111111.agents.fence.dev",
      nonce: "cross-verify-nonce",
    });

    const verifyRequest = {
      method: request.method,
      url: request.url,
      headers: {
        ...toHeaderRecord(request),
        Signature: signatureHeaders.Signature,
        "Signature-Input": signatureHeaders["Signature-Input"],
      },
    };

    const verified = await httpbis.verifyMessage(
      {
        keyLookup: () => Promise.resolve(independentEd25519Verifier(publicKey)),
      },
      verifyRequest,
    );

    expect(verified).toBe(true);
    void privateKey; // exercised inside signAgentRequest via signingKey
  });

  it("is rejected by the independent verifier when the signed body is tampered with after signing", async () => {
    const { publicKey, privateKeyJwk } = await generateEd25519KeyPair();
    const signingKey = await importAgentSigningKey(privateKeyJwk);
    const request = { method: "GET", url: "https://rp.example.com/orders/42", headers: {} };

    const signatureHeaders = await signAgentRequest(request, {
      signingKey,
      keyId: "agent-key-1",
      signatureAgent: "https://11111111-1111-1111-1111-111111111111.agents.fence.dev",
      nonce: "cross-verify-nonce-2",
    });

    // Tamper with the covered @authority component after signing, by
    // presenting a different URL to the independent verifier — the
    // Signature-Agent header (also covered) is left untouched, isolating
    // the failure to the @authority mismatch.
    const tamperedRequest = {
      method: request.method,
      url: "https://attacker.example.com/orders/42",
      headers: {
        ...toHeaderRecord(request),
        Signature: signatureHeaders.Signature,
        "Signature-Input": signatureHeaders["Signature-Input"],
      },
    };

    const verified = await httpbis.verifyMessage(
      {
        keyLookup: () => Promise.resolve(independentEd25519Verifier(publicKey)),
      },
      tamperedRequest,
    );

    expect(verified).toBe(false);
  });
});
