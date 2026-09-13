// RP-side verification of a Self-Issued ID Token.
// OpenID Connect Core 1.0 Section 7.5, plus the ID Token checks of Section 3.2.2.11.
// Pure ES module: no DOM access, so it runs in the browser and under Node.
//
// It speaks no language. A value that came from the request or the token is
// returned as the string it is; anything else is a note — `{ note: "none" }`,
// `{ note: "segments", count: 3 }` — for the page to put into words.

export const SELF_ISSUED_ISSUER = "https://self-issued.me";

export function base64urlDecode(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(base64);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export function base64urlEncode(bytes) {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// The members RFC 7638 hashes, in lexicographic order and without
/// whitespace — the exact input to the thumbprint.
export function canonicalJWK(jwk) {
  return JSON.stringify({ e: jwk.e, kty: jwk.kty, n: jwk.n });
}

/// RFC 7638 JWK thumbprint: SHA-256 over the canonical JSON of the required
/// members.
export async function jwkThumbprint(jwk) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonicalJWK(jwk)));
  return base64urlEncode(new Uint8Array(digest));
}

const NONE = { note: "none" };
const valueOf = (value) => (value === undefined || value === null || value === "" ? NONE : String(value));

/// What an expectation reads as: the value sent, or why there is none to
/// compare against.
const expectation = (value) => {
  if (value === undefined) return { note: "notCompared" };
  if (value === null) return { note: "noRecord" };
  return value;
};

/// Section 3.1.2.1: the `state` in the fragment must be the one this browser
/// sent. It travels outside the token, so it is checked apart from it.
///
/// `sent` is "" when the request carried no state, and null when this browser
/// has no record of the request at all — which fails rather than passes.
export function checkState(sent, received) {
  const hasRecord = sent !== null && sent !== undefined;
  const ok = hasRecord && sent === (received ?? "");
  return {
    id: "state",
    ok,
    expected: !hasRecord ? { note: "noRecord" } : sent === "" ? { note: "omitted" } : sent,
    actual: received ? received : { note: "omitted" },
  };
}

/// Runs every check and reports each one, rather than throwing on the first
/// failure, so the result can be shown as a checklist: each check carries what
/// was expected beside what arrived.
///
/// `audience` and `nonce` are what this RP sent. Leaving one out skips that
/// comparison; passing null — no record of the request — fails it.
export async function verifySelfIssuedIDToken(idToken, { audience, nonce, now = Date.now() / 1000, clockSkewSeconds = 120 } = {}) {
  const checks = [];
  const record = (id, ok, expected, actual) => {
    checks.push({ id, ok, expected, actual });
    return ok;
  };
  const fail = (id, expected, actual) => {
    record(id, false, expected, actual);
    return { ok: false, checks, header: null, payload: null };
  };

  const jws = { note: "jws" };
  const parts = String(idToken).split(".");
  if (parts.length !== 3) {
    return fail("structure", jws, { note: "segments", count: parts.length });
  }

  let header, payload, signature;
  try {
    header = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
    signature = base64urlDecode(parts[2]);
  } catch {
    return fail("structure", jws, { note: "undecodable" });
  }
  record("structure", true, jws, { note: "segments", count: 3 });

  // Section 7.1: RS256 is the algorithm a Self-Issued OP must support.
  record("alg", header.alg === "RS256", "RS256", valueOf(header.alg));

  // Section 7.5 (2)
  record("iss", payload.iss === SELF_ISSUED_ISSUER, SELF_ISSUED_ISSUER, valueOf(payload.iss));

  // Section 7.5 (3)
  const jwk = payload.sub_jwk;
  const hasJWK = Boolean(jwk) && jwk.kty === "RSA" && typeof jwk.n === "string" && typeof jwk.e === "string";
  record("sub_jwk", hasJWK, { note: "rsaKeyMembers" }, { note: hasJWK ? "rsaKey" : "notRsaKey" });

  // Section 7.5 (4): sub must be the thumbprint of sub_jwk, which is what binds
  // the identifier to the key — without it the subject could be claimed freely.
  let thumbprint = null;
  if (hasJWK) {
    thumbprint = await jwkThumbprint(jwk);
    record("sub", payload.sub === thumbprint, thumbprint, valueOf(payload.sub));
  } else {
    record("sub", false, { note: "noKeyToDerive" }, valueOf(payload.sub));
  }

  // Section 7.5 (5)
  const valid = { note: "validSignature" };
  if (hasJWK && header.alg === "RS256") {
    let actual;
    let verified = false;
    try {
      const key = await crypto.subtle.importKey(
        "jwk",
        { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"],
      );
      verified = await crypto.subtle.verify(
        { name: "RSASSA-PKCS1-v1_5" },
        key,
        signature,
        new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
      );
      actual = verified ? valid : { note: "invalidSignature" };
    } catch (error) {
      actual = { note: "unverifiable", reason: error.message };
    }
    record("signature", verified, valid, actual);
  } else {
    record("signature", false, valid, { note: "badKeyOrAlg" });
  }

  // Section 3.2.2.11: the token must be addressed to this RP.
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  const audOK = audience === undefined || audiences.includes(audience);
  record("aud", audOK, expectation(audience), valueOf(audiences.filter(Boolean).join(", ")));

  // The nonce binds the token to this authentication request (replay protection).
  const nonceOK = nonce === undefined || payload.nonce === nonce;
  record("nonce", nonceOK, expectation(nonce), valueOf(payload.nonce));

  const iso = (seconds) => new Date(seconds * 1000).toISOString();
  const expOK = typeof payload.exp === "number" && now < payload.exp + clockSkewSeconds;
  record("exp", expOK,
    { note: "after", time: iso(now), skew: clockSkewSeconds },
    typeof payload.exp === "number" ? iso(payload.exp) : NONE);

  return { ok: checks.every((check) => check.ok), checks, header, payload, thumbprint };
}
