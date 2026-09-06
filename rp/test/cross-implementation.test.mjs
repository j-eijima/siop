// Runs the same assertions as verify.test.mjs against a token issued by the
// *current* Swift build rather than the committed fixture, so that a change to
// SIOPKit that breaks interoperability is caught rather than papered over by a
// stale fixture.
//
// Needs a Swift toolchain; skipped automatically when `swift` is unavailable,
// which keeps `node --test test/` runnable anywhere.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { AUDIENCE, NONCE, claimsOf, describeIssuedToken } from "./shared.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const packagePath = resolve(here, "../../ios/SIOPKit");

function swiftAvailable() {
  try {
    execFileSync("swift", ["--version"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

if (!swiftAvailable()) {
  describe("現在の Swift 実装との突き合わせ", { skip: "Swift ツールチェインがありません" }, () => {
    it("skipped", () => {});
  });
} else {
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
      { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
    ));
  };

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
