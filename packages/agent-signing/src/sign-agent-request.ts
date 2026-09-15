import type { FieldOccurrence, RequestDescriptor } from "http-message-sig";
import { createSignature } from "http-message-sig";
import { AgentSigningError } from "./agent-signing-error.js";
import { ed25519Signer } from "./ed25519-signer.js";

// The exact Web Bot Auth draft wire conventions this package's checklist
// item (§1.7.5a) fixes: tag="web-bot-auth", @authority + signature-agent
// as the covered components, alg="ed25519" (via ed25519Signer). Not
// caller-configurable — a signer that let these drift per-call would stop
// being interoperable with a generic Web Bot Auth verifier, which is the
// entire point of this package.
const WEB_BOT_AUTH_TAG = "web-bot-auth";
const REQUIRED_ALGORITHM = "ed25519";
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

// http-message-sig 0.2.0 exported RequestLike/HeaderValue directly (a
// Headers-like get()/set() map, or a plain Record<string, string | string[]
// | {toString()}>) — 0.3.0 has no equivalent public type at all (its own
// message shape is a real Fetch API Request, or a RequestDescriptor with a
// pre-built `fields` array, neither of which supports "mutate this header
// in place" the way this function's callers rely on). Redefined locally
// here, deliberately narrower than 0.2.0's own union (string values only,
// no array/toString() header-value variants) — the two shapes below are
// the only ones this package's own tests, and every real caller in this
// workspace (confirmed by a workspace-wide grep: nothing imports
// RequestLike/HeaderValue from this package today), have ever used.
export type HeaderValue = string;
export interface HeadersMapLike {
  get(name: string): string | null;
  set(name: string, value: string): void;
}
export interface RequestLike {
  readonly method: string;
  readonly url: string;
  readonly headers: Record<string, HeaderValue> | HeadersMapLike;
}

// Signs `request` in place (the Signature-Agent header is written onto it)
// and returns the three headers a caller sends alongside it. Fails closed
// with AgentSigningError on every failure mode — a wrong-algorithm key, a
// signing failure, or any unexpected error from http-message-sig itself —
// never surfacing signing material in the thrown error.
export async function signAgentRequest(request: RequestLike, options: SignAgentRequestOptions): Promise<AgentSignatureHeaders> {
  const signer = ed25519Signer(options.signingKey);
  setHeader(request.headers, "Signature-Agent", options.signatureAgent);

  const created = options.now ?? new Date();
  const expiresInSeconds = options.expiresInSeconds ?? DEFAULT_EXPIRES_IN_SECONDS;
  const expires = new Date(created.getTime() + expiresInSeconds * MILLISECONDS_PER_SECOND);

  // 0.3.0's own RequestDescriptor wants a fully pre-built `fields` array
  // rather than something to read headers off of live — "signature-agent"
  // is the only field either covered component actually needs (@authority
  // is derived from targetUri), so that's the only entry built here.
  const descriptor: RequestDescriptor = {
    kind: "request",
    method: request.method,
    targetUri: request.url,
    fields: [{ name: "signature-agent", value: options.signatureAgent }] satisfies FieldOccurrence[],
  };

  try {
    const fields = await createSignature(descriptor, {
      components: COVERED_COMPONENTS,
      parameters: {
        created: Math.floor(created.getTime() / MILLISECONDS_PER_SECOND),
        expires: Math.floor(expires.getTime() / MILLISECONDS_PER_SECOND),
        nonce: options.nonce,
        keyid: options.keyId,
        alg: REQUIRED_ALGORITHM,
        tag: WEB_BOT_AUTH_TAG,
      },
      signer,
    });
    return {
      Signature: fields.signature,
      "Signature-Input": fields.signatureInput,
      "Signature-Agent": options.signatureAgent,
    };
  } catch (cause) {
    if (cause instanceof AgentSigningError) throw cause;
    throw new AgentSigningError("agent-signing: failed to produce signature headers");
  }
}

function isHeadersMap(headers: RequestLike["headers"]): headers is HeadersMapLike {
  return "set" in headers && typeof headers.set === "function";
}

function setHeader(headers: RequestLike["headers"], name: string, value: string): void {
  if (isHeadersMap(headers)) {
    headers.set(name, value);
    return;
  }
  // eslint-disable-next-line security/detect-object-injection -- `name` is always this module's own literal "Signature-Agent", never caller-supplied
  headers[name] = value;
}
