// Assertions shared by the fixture suite and the live cross-implementation
// suite, so both hold the RP verifier to exactly the same standard.
// Not a test file itself: keeping it out of `*.test.mjs` stops the runner from
// executing the shared suite twice.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { base64urlDecode, base64urlEncode, jwkThumbprint, verifySelfIssuedIDToken } from "../public/siop-verify.js";

export const AUDIENCE = "http://localhost:8080/callback.html";
export const NONCE = "n-0S6_WzA2Mj";

export function claimsOf(idToken) {
  return JSON.parse(new TextDecoder().decode(base64urlDecode(idToken.split(".")[1])));
}

/// Tokens have a fixed lifetime, so verify at a fixed instant rather than at
/// wall-clock time — otherwise the fixture suite would start failing once the
/// recorded token expires.
export const validAt = (idToken) => claimsOf(idToken).iat + 1;

export function reencode(idToken, mutate) {
  const parts = idToken.split(".");
  const payload = claimsOf(idToken);
  mutate(payload);
  parts[1] = base64urlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  return parts.join(".");
}

export const checkFor = (result, id) => result.checks.find((check) => check.id === id);

/// `load` returns { idToken, expectedSubject } for the token under test.
export function describeIssuedToken(title, load) {
  describe(title, () => {
    let idToken;
    let expectedSubject;
    const at = () => validAt(idToken);

    it("トークンを用意できる", async () => {
      ({ idToken, expectedSubject } = await load());
      assert.ok(idToken);
    });

    it("正しいトークンは全項目を通過する", async () => {
      const result = await verifySelfIssuedIDToken(idToken, { audience: AUDIENCE, nonce: NONCE, now: at() });
      const failed = result.checks.filter((check) => !check.ok);
      assert.deepEqual(failed, [], `失敗した項目: ${failed.map((c) => c.id).join(", ")}`);
      assert.equal(result.ok, true);
      assert.equal(result.payload.iss, "https://self-issued.me");
      // Both implementations must derive the same subject from the same key.
      assert.equal(result.payload.sub, expectedSubject);
      assert.equal(await jwkThumbprint(result.payload.sub_jwk), expectedSubject);
    });

    it("ペイロードを書き換えると署名検証に失敗する", async () => {
      const tampered = reencode(idToken, (payload) => {
        payload.aud = "https://attacker.example/cb";
      });
      const result = await verifySelfIssuedIDToken(tampered, {
        audience: "https://attacker.example/cb", nonce: NONCE, now: at(),
      });
      assert.equal(result.ok, false);
      assert.equal(checkFor(result, "signature").ok, false);
    });

    it("sub を差し替えるとサムプリント照合に失敗する", async () => {
      const tampered = reencode(idToken, (payload) => {
        payload.sub = "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs";
      });
      const result = await verifySelfIssuedIDToken(tampered, { audience: AUDIENCE, nonce: NONCE, now: at() });
      assert.equal(checkFor(result, "sub").ok, false);
      assert.equal(checkFor(result, "signature").ok, false);
    });

    it("別の RP 宛てのトークンは aud で弾かれる", async () => {
      const result = await verifySelfIssuedIDToken(idToken, {
        audience: "https://other.example/cb", nonce: NONCE, now: at(),
      });
      assert.equal(result.ok, false);
      assert.equal(checkFor(result, "aud").ok, false);
      assert.equal(checkFor(result, "signature").ok, true);
    });

    it("nonce が違うトークンは弾かれる", async () => {
      const result = await verifySelfIssuedIDToken(idToken, {
        audience: AUDIENCE, nonce: "another-nonce", now: at(),
      });
      assert.equal(result.ok, false);
      assert.equal(checkFor(result, "nonce").ok, false);
    });

    it("期限を過ぎたトークンは弾かれる", async () => {
      const result = await verifySelfIssuedIDToken(idToken, {
        audience: AUDIENCE, nonce: NONCE, now: claimsOf(idToken).exp + 3600,
      });
      assert.equal(result.ok, false);
      assert.equal(checkFor(result, "exp").ok, false);
      assert.equal(checkFor(result, "signature").ok, true);
    });
  });
}
