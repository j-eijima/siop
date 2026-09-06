// Runs the same assertions as verify.test.mjs against a token issued by the
// *current* Swift build rather than the committed fixture, so that a change to
// SIOPKit that breaks interoperability is caught rather than papered over by a
// stale fixture.
//
// Needs a working SIOPKit build; skipped automatically when one is not
// available, which keeps `node --test` runnable anywhere. Note that the
// presence of a `swift` binary is not enough to go on: GitHub's Linux runners
// ship Swift, but SIOPKit builds on Security and CryptoKit and so only builds
// on Apple platforms. The probe therefore issues a token for real.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { AUDIENCE, NONCE, claimsOf, describeIssuedToken } from "./shared.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const packagePath = resolve(here, "../../ios/SIOPKit");

const issue = () => {
  const params = new URLSearchParams({
    response_type: "id_token",
    client_id: AUDIENCE,
    scope: "openid",
    nonce: NONCE,
    state: "st1",
  });
  return JSON.parse(execFileSync(
    "swift",
    ["run", "--package-path", packagePath, "siop-issue", `openid://?${params}`],
    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
  ));
};

/// Can this machine actually get a token out of SIOPKit? Building it is the
/// only honest answer, so the probe does exactly that.
function unavailableReason() {
  try {
    issue();
    return null;
  } catch (error) {
    return `SIOPKit をビルドできません (${error.code ?? error.message})`;
  }
}

const skipReason = unavailableReason();

if (skipReason) {
  describe("現在の Swift 実装との突き合わせ", { skip: skipReason }, () => {
    it("skipped", () => {});
  });
} else {

  describeIssuedToken("現在の Swift 実装が発行した ID Token", async () => {
    const issued = issue();
    return { idToken: issued.id_token, expectedSubject: issued.sub };
  });

  describe("フィクスチャ", () => {
    it("現在の実装と同じ形のトークンである", () => {
      const fixture = JSON.parse(readFileSync(resolve(here, "fixtures/swift-issued.json"), "utf8"));
      const fresh = issue();
      const shapeOf = (token) => Object.keys(claimsOf(token)).sort();
      assert.deepEqual(shapeOf(fixture.id_token), shapeOf(fresh.id_token),
        "クレーム構成が変わっています。test/fixtures/regenerate.sh を実行してください");
      assert.equal(claimsOf(fixture.id_token).iss, claimsOf(fresh.id_token).iss);
    });
  });
}
