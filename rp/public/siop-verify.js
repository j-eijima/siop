// RP-side verification of a Self-Issued ID Token.
// OpenID Connect Core 1.0 Section 7.5, plus the ID Token checks of Section 3.2.2.11.
// Pure ES module: no DOM access, so it runs in the browser and under Node.

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

/// RFC 7638 JWK thumbprint: SHA-256 over the canonical JSON of the required
/// members, in lexicographic order.
export async function jwkThumbprint(jwk) {
  const canonical = JSON.stringify({ e: jwk.e, kty: jwk.kty, n: jwk.n });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return base64urlEncode(new Uint8Array(digest));
}

/// Runs every check and reports each one, rather than throwing on the first
/// failure, so the result can be shown as a checklist.
export async function verifySelfIssuedIDToken(idToken, { audience, nonce, now = Date.now() / 1000, clockSkewSeconds = 120 } = {}) {
  const checks = [];
  const record = (id, title, ok, detail) => {
    checks.push({ id, title, ok, detail });
    return ok;
  };
  const fail = (id, title, detail) => {
    record(id, title, false, detail);
    return { ok: false, checks, header: null, payload: null };
  };

  const parts = String(idToken).split(".");
  if (parts.length !== 3) {
    return fail("structure", "JWS 形式", `3 つのセグメントが必要ですが ${parts.length} 個です`);
  }

  let header, payload, signature;
  try {
    header = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
    signature = base64urlDecode(parts[2]);
  } catch (error) {
    return fail("structure", "JWS 形式", `デコードできません: ${error.message}`);
  }
  record("structure", "JWS 形式", true, "ヘッダ・ペイロード・署名に分解できました");

  // Section 7.1: RS256 is the algorithm a Self-Issued OP must support.
  record("alg", "alg = RS256", header.alg === "RS256", `alg: ${header.alg ?? "(なし)"}`);

  // Section 7.5 (2)
  record("iss", `iss = ${SELF_ISSUED_ISSUER}`, payload.iss === SELF_ISSUED_ISSUER, `iss: ${payload.iss ?? "(なし)"}`);

  // Section 7.5 (3)
  const jwk = payload.sub_jwk;
  const hasJWK = Boolean(jwk) && jwk.kty === "RSA" && typeof jwk.n === "string" && typeof jwk.e === "string";
  record("sub_jwk", "sub_jwk に RSA 公開鍵がある", hasJWK, hasJWK ? `kty: ${jwk.kty}` : "RSA 公開鍵として読めません");

  // Section 7.5 (4): sub must be the thumbprint of sub_jwk, which is what binds
  // the identifier to the key — without it the subject could be claimed freely.
  let thumbprint = null;
  if (hasJWK) {
    thumbprint = await jwkThumbprint(jwk);
    record("sub", "sub = sub_jwk のサムプリント", payload.sub === thumbprint,
      payload.sub === thumbprint ? `sub: ${payload.sub}` : `sub: ${payload.sub ?? "(なし)"} / 期待値: ${thumbprint}`);
  } else {
    record("sub", "sub = sub_jwk のサムプリント", false, "sub_jwk が無いため検証できません");
  }

  // Section 7.5 (5)
  if (hasJWK && header.alg === "RS256") {
    let verified = false;
    let detail = "";
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
      detail = verified ? "sub_jwk の鍵で署名を検証しました" : "署名が一致しません";
    } catch (error) {
      detail = `検証できません: ${error.message}`;
    }
    record("signature", "署名の検証", verified, detail);
  } else {
    record("signature", "署名の検証", false, "鍵または alg が不正なため検証できません");
  }

  // Section 3.2.2.11: the token must be addressed to this RP.
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  const audOK = audience === undefined || audiences.includes(audience);
  record("aud", "aud がこの RP 宛て", audOK, `aud: ${audiences.join(", ") || "(なし)"}`);

  // The nonce binds the token to this authentication request (replay protection).
  const nonceOK = nonce === undefined || payload.nonce === nonce;
  record("nonce", "nonce が要求時の値と一致", nonceOK,
    nonceOK ? `nonce: ${payload.nonce ?? "(なし)"}` : `nonce: ${payload.nonce ?? "(なし)"} / 期待値: ${nonce}`);

  const expOK = typeof payload.exp === "number" && now < payload.exp + clockSkewSeconds;
  record("exp", "有効期限内", expOK, payload.exp ? `exp: ${new Date(payload.exp * 1000).toISOString()}` : "exp がありません");

  return { ok: checks.every((check) => check.ok), checks, header, payload, thumbprint };
}
