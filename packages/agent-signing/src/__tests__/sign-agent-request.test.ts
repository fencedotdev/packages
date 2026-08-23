import { describe, expect, it } from "vitest";
import { AgentSigningError } from "../agent-signing-error.js";
import { importAgentSigningKey } from "../ed25519-signing-key.js";
import { signAgentRequest } from "../sign-agent-request.js";
import { generateEd25519KeyPair } from "./generate-ed25519-key-pair.js";

async function generateSigningKey(): Promise<CryptoKey> {
  const { privateKeyJwk } = await generateEd25519KeyPair();
  return importAgentSigningKey(privateKeyJwk);
}

function newRequest(): { method: string; url: string; headers: Record<string, string> } {
  return { method: "GET", url: "https://rp.example.com/orders/42", headers: {} };
}

function baseOptions(signingKey: CryptoKey) {
  return {
    signingKey,
    keyId: "agent-signing-key-1",
    signatureAgent: "https://11111111-1111-1111-1111-111111111111.agents.fence.dev",
    nonce: "test-nonce-1",
    now: new Date("2026-08-23T12:00:00.000Z"),
  };
}

describe("signAgentRequest", () => {
  it("returns Signature, Signature-Input, and Signature-Agent headers", async () => {
    const signingKey = await generateSigningKey();
    const request = newRequest();

    const headers = await signAgentRequest(request, baseOptions(signingKey));

    expect(headers.Signature).toEqual(expect.stringContaining("sig1=:"));
    expect(headers["Signature-Input"]).toEqual(expect.stringContaining('sig1=("@authority" "signature-agent")'));
    expect(headers["Signature-Agent"]).toBe("https://11111111-1111-1111-1111-111111111111.agents.fence.dev");
  });

  it("sets the Signature-Agent header on the request it signs", async () => {
    const signingKey = await generateSigningKey();
    const request = newRequest();

    await signAgentRequest(request, baseOptions(signingKey));

    expect(request.headers["Signature-Agent"]).toBe("https://11111111-1111-1111-1111-111111111111.agents.fence.dev");
  });

  it("carries the web-bot-auth tag, ed25519 alg, and the given nonce in Signature-Input", async () => {
    const signingKey = await generateSigningKey();
    const request = newRequest();

    const headers = await signAgentRequest(request, baseOptions(signingKey));

    expect(headers["Signature-Input"]).toEqual(expect.stringContaining('tag="web-bot-auth"'));
    expect(headers["Signature-Input"]).toEqual(expect.stringContaining('alg="ed25519"'));
    expect(headers["Signature-Input"]).toEqual(expect.stringContaining('nonce="test-nonce-1"'));
    expect(headers["Signature-Input"]).toEqual(expect.stringContaining("created=1787486400"));
  });

  it("defaults expires to 5 minutes after created when not given", async () => {
    const signingKey = await generateSigningKey();
    const request = newRequest();

    const headers = await signAgentRequest(request, baseOptions(signingKey));

    expect(headers["Signature-Input"]).toEqual(expect.stringContaining("expires=1787486700"));
  });

  it("honours an explicit expiresInSeconds", async () => {
    const signingKey = await generateSigningKey();
    const request = newRequest();

    const headers = await signAgentRequest(request, { ...baseOptions(signingKey), expiresInSeconds: 30 });

    expect(headers["Signature-Input"]).toEqual(expect.stringContaining("expires=1787486430"));
  });

  it("fails closed with AgentSigningError when handed a non-Ed25519 CryptoKey", async () => {
    const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    const request = newRequest();

    await expect(signAgentRequest(request, baseOptions(privateKey))).rejects.toThrow(AgentSigningError);
  });

  it("fails closed with AgentSigningError, without leaking the underlying WebCrypto error, when the key passes the algorithm check but cannot actually sign", async () => {
    // An Ed25519 public key: algorithm.name is "Ed25519" (passes ed25519Signer's
    // own type-narrowing guard), but crypto.subtle.sign() itself rejects it —
    // exercises ed25519Signer's own try/catch around the real sign() call,
    // and signAgentRequest's "rethrow an AgentSigningError from inside the try
    // block unchanged" branch (the signer already wrapped it once).
    const { publicKey } = await generateEd25519KeyPair();
    const request = newRequest();

    await expect(signAgentRequest(request, baseOptions(publicKey))).rejects.toThrow(AgentSigningError);
    await expect(signAgentRequest(request, baseOptions(publicKey))).rejects.toThrow("agent-signing: signing failed");
  });

  it("wraps a failure unrelated to the signer itself (e.g. a malformed request URL) into a generic AgentSigningError", async () => {
    const signingKey = await generateSigningKey();
    const request = { method: "GET", url: "not-a-valid-url", headers: {} };

    await expect(signAgentRequest(request, baseOptions(signingKey))).rejects.toThrow(AgentSigningError);
    await expect(signAgentRequest(request, baseOptions(signingKey))).rejects.toThrow("agent-signing: failed to produce signature headers");
  });

  it("works against a HeadersMap-shaped request (get/set), not just a plain header object", async () => {
    const signingKey = await generateSigningKey();
    const store = new Map<string, string>();
    const request = {
      method: "GET",
      url: "https://rp.example.com/orders/42",
      headers: {
        get: (name: string) => store.get(name.toLowerCase()) ?? null,
        set: (name: string, value: string) => {
          store.set(name.toLowerCase(), value);
        },
      },
    };

    const headers = await signAgentRequest(request, baseOptions(signingKey));

    expect(headers["Signature-Agent"]).toBe(store.get("signature-agent"));
  });
});
