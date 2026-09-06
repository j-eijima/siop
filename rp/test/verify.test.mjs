// Verifies real ID Tokens signed by the other implementations, using the RP's
// JavaScript implementation of OpenID Connect Core Section 7.5.
//
// The tokens are committed fixtures produced by each implementation's
// siop-issue, so this suite needs nothing but Node. Checking against a live
// build is `cross-implementation.test.mjs`.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { describe, it } from "node:test";

import { jwkThumbprint, verifySelfIssuedIDToken } from "../public/siop-verify.js";
import { AUDIENCE, NONCE, checkFor, describeIssuedToken } from "./shared.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const fixture = (name) => JSON.parse(readFileSync(resolve(here, `fixtures/${name}`), "utf8"));

// Every implementation that issues tokens is checked here, so that none is
// only ever verified by itself.
for (const [implementation, file] of [
  ["Swift (ios/SIOPKit)", "swift-issued.json"],
  ["Kotlin (android/siopkit)", "kotlin-issued.json"],
]) {
  describeIssuedToken(`${implementation} が署名した ID Token (フィクスチャ)`, async () => {
    const issued = fixture(file);
    return { idToken: issued.id_token, expectedSubject: issued.sub };
  });
}

describe("形式が壊れたトークン", () => {
  it("形式チェックで止まる", async () => {
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
