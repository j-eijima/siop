// Cross-implementation test: tokens signed by the Swift SIOPKit are verified
// by the RP's JavaScript implementation of OpenID Connect Core Section 7.5.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { after, before, describe, it } from "node:test";

import { base64urlDecode, base64urlEncode, jwkThumbprint, verifySelfIssuedIDToken } from "../public/siop-verify.js";

const here = dirname(fileURLToPath(import.meta.url));
const packagePath = resolve(here, "../../ios/SIOPKit");

const AUDIENCE = "http://localhost:8080/callback.html";
const NONCE = "n-0S6_WzA2Mj";

/// Issues a real token with the Swift implementation.
function issue({ expired = false } = {}) {
  const params = new URLSearchParams({
    response_type: "id_token",
    client_id: AUDIENCE,
    scope: "openid",
    nonce: NONCE,
    state: "st1",
  });
  const args = ["run", "--package-path", packagePath, "siop-issue", `openid://?${params}`];
  if (expired) args.push("--expired");
  return JSON.parse(execFileSync("swift", args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }));
}

function reencode(idToken, mutate) {
  const parts = idToken.split(".");
  const payload = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
  mutate(payload);
  parts[1] = base64urlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  return parts.join(".");
}

const checkFor = (result, id) => result.checks.find((check) => check.id === id);

describe("Swift が発行した ID Token の検証", () => {
  let issued;
  before(() => {
    issued = issue();
  });

  it("正しいトークンは全項目を通過する", async () => {
    const result = await verifySelfIssuedIDToken(issued.id_token, { audience: AUDIENCE, nonce: NONCE });
    const failed = result.checks.filter((check) => !check.ok);
    assert.deepEqual(failed, [], `失敗した項目: ${failed.map((c) => c.id).join(", ")}`);
    assert.equal(result.ok, true);
    assert.equal(result.payload.iss, "https://self-issued.me");
    // Both implementations must derive the same subject from the same key.
    assert.equal(result.payload.sub, issued.sub);
    assert.equal(await jwkThumbprint(result.payload.sub_jwk), issued.sub);
  });

  it("ペイロードを書き換えると署名検証に失敗する", async () => {
    const tampered = reencode(issued.id_token, (payload) => {
      payload.aud = "https://attacker.example/cb";
    });
    const result = await verifySelfIssuedIDToken(tampered, { audience: "https://attacker.example/cb", nonce: NONCE });
    assert.equal(result.ok, false);
    assert.equal(checkFor(result, "signature").ok, false);
  });

  it("sub を差し替えるとサムプリント照合に失敗する", async () => {
    const tampered = reencode(issued.id_token, (payload) => {
      payload.sub = "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs";
    });
    const result = await verifySelfIssuedIDToken(tampered, { audience: AUDIENCE, nonce: NONCE });
    assert.equal(checkFor(result, "sub").ok, false);
    assert.equal(checkFor(result, "signature").ok, false);
  });

  it("別の RP 宛てのトークンは aud で弾かれる", async () => {
    const result = await verifySelfIssuedIDToken(issued.id_token, {
      audience: "https://other.example/cb",
      nonce: NONCE,
    });
    assert.equal(result.ok, false);
    assert.equal(checkFor(result, "aud").ok, false);
    assert.equal(checkFor(result, "signature").ok, true);
  });

  it("nonce が違うトークンは弾かれる", async () => {
    const result = await verifySelfIssuedIDToken(issued.id_token, { audience: AUDIENCE, nonce: "another-nonce" });
    assert.equal(result.ok, false);
    assert.equal(checkFor(result, "nonce").ok, false);
  });

  it("期限切れのトークンは弾かれる", async () => {
    const expired = issue({ expired: true });
    const result = await verifySelfIssuedIDToken(expired.id_token, { audience: AUDIENCE, nonce: NONCE });
    assert.equal(result.ok, false);
    assert.equal(checkFor(result, "exp").ok, false);
    assert.equal(checkFor(result, "signature").ok, true);
  });

  it("壊れたトークンは形式チェックで止まる", async () => {
    const result = await verifySelfIssuedIDToken("not-a-jwt", { audience: AUDIENCE, nonce: NONCE });
    assert.equal(result.ok, false);
    assert.equal(result.checks.length, 1);
    assert.equal(checkFor(result, "structure").ok, false);
  });
});

describe("RFC 7638", () => {
  it("仕様の例と同じサムプリントを算出する", async () => {
    const jwk = {
      kty: "RSA",
      n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
      e: "AQAB",
    };
    assert.equal(await jwkThumbprint(jwk), "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs");
  });
});
