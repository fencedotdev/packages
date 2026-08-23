import type { RequestLike } from "http-message-sig";
import { signatureHeaders } from "http-message-sig";
import { AgentSigningError } from "./agent-signing-error.js";
import { ed25519Signer } from "./ed25519-signer.js";

// The exact Web Bot Auth draft wire conventions this package's checklist
// item (§1.7.5a) fixes: tag="web-bot-auth", @authority + signature-agent
// as the covered components, alg="ed25519" (via ed25519Signer). Not
// caller-configurable — a signer that let these drift per-call would stop
// being interoperable with a generic Web Bot Auth verifier, which is the
// entire point of this package.
const WEB_BOT_AUTH_TAG = "web-bot-auth";
const COVERED_COMPONENTS = ["@authority", "signature-agent"];
const DEFAULT_EXPIRES_IN_SECONDS = 300;
const MILLISECONDS_PER_SECOND = 1000;

export interface SignAgentRequestOptions {
  readonly signingKey: CryptoKey;
  readonly keyId: string;
  // The .well-known key-discovery hostname a generic verifier resolves
  // this signature against (§1.7.5b) — e.g.
  // "https://{agentId}.agents.fence.dev". Set verbatim as the request's
  // Signature-Agent header and covered by the signature itself.
  readonly signatureAgent: string;
  // Required, not generated internally — this package has no opinion on
  // nonce-uniqueness storage (that's the verifier's replay-tracking
  // concern, explicitly out of scope here), so the caller supplies one
  // fresh per request.
  readonly nonce: string;
  readonly now?: Date;
  readonly expiresInSeconds?: number;
}

export interface AgentSignatureHeaders {
  readonly Signature: string;
  readonly "Signature-Input": string;
  readonly "Signature-Agent": string;
}

// Signs `request` in place (the Signature-Agent header is written onto it)
// and returns the three headers a caller sends alongside it. Fails closed
// with AgentSigningError on every failure mode — a wrong-algorithm key, a
// signing failure, or any unexpected error from http-message-sig itself —
// never surfacing signing material in the thrown error.
export async function signAgentRequest(request: RequestLike, options: SignAgentRequestOptions): Promise<AgentSignatureHeaders> {
  const signer = ed25519Signer(options.signingKey, options.keyId);
  setHeader(request.headers, "Signature-Agent", options.signatureAgent);

  const created = options.now ?? new Date();
  const expiresInSeconds = options.expiresInSeconds ?? DEFAULT_EXPIRES_IN_SECONDS;
  const expires = new Date(created.getTime() + expiresInSeconds * MILLISECONDS_PER_SECOND);

  try {
    const headers = await signatureHeaders(request, {
      components: COVERED_COMPONENTS,
      tag: WEB_BOT_AUTH_TAG,
      created,
      expires,
      nonce: options.nonce,
      signer,
    });
    return { ...headers, "Signature-Agent": options.signatureAgent };
  } catch (cause) {
    if (cause instanceof AgentSigningError) throw cause;
    throw new AgentSigningError("agent-signing: failed to produce signature headers");
  }
}

// http-message-sig's own `HeadersMap` type isn't exported from its public
// API — narrowed structurally here instead of importing it by name.
type RequestHeaders = RequestLike["headers"];
type HeadersMapLike = Extract<RequestHeaders, { set: (name: string, value: string) => void }>;

function isHeadersMap(headers: RequestHeaders): headers is HeadersMapLike {
  return "set" in headers && typeof headers.set === "function";
}

function setHeader(headers: RequestHeaders, name: string, value: string): void {
  if (isHeadersMap(headers)) {
    headers.set(name, value);
    return;
  }
  // eslint-disable-next-line security/detect-object-injection -- `name` is always this module's own literal "Signature-Agent", never caller-supplied
  headers[name] = value;
}
