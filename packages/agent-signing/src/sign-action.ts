import { canonicalizeAction, type Action } from "@fence.dev/contracts";
import { AgentSigningError } from "./agent-signing-error.js";
import { assertEd25519SigningKey } from "./ed25519-signing-key-guard.js";

// Produces the raw Ed25519 signature verification's own
// verifyRequestSignature() expects for M·3 request binding: a signature
// over canonicalizeAction(action), base64url-encoded (no padding). This is
// a DIFFERENT signature from signAgentRequest()'s RFC 9421 / Web Bot Auth
// request headers — these are two independent signatures for two
// independent purposes; do not conflate them.
export async function signAction(action: Action, signingKey: CryptoKey): Promise<string> {
  assertEd25519SigningKey(signingKey);

  let signature: ArrayBuffer;
  try {
    signature = await crypto.subtle.sign("Ed25519", signingKey, new TextEncoder().encode(canonicalizeAction(action)));
  } catch {
    throw new AgentSigningError("agent-signing: signing failed");
  }

  return toBase64Url(new Uint8Array(signature));
}

// No Buffer — this package stays Node-independent/WebCrypto-only.
function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
