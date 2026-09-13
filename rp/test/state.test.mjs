// The state travels in the fragment, outside the token, so the RP checks it
// apart from the ID Token. A pure comparison, so no token is needed.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { checkState } from "../public/siop-verify.js";

describe("state の照合", () => {
  it("送った値と同じなら通る", () => {
    assert.equal(checkState("af0ifjsldkj", "af0ifjsldkj").ok, true);
  });

  it("違えば通らず、両方の値を示す", () => {
    const check = checkState("af0ifjsldkj", "tampered");
    assert.equal(check.ok, false);
    assert.equal(check.expected, "af0ifjsldkj");
    assert.equal(check.actual, "tampered");
  });

  it("送らず、返ってもこなければ通る", () => {
    assert.equal(checkState("", null).ok, true);
  });

  it("送っていないのに返ってきたら通らない", () => {
    assert.equal(checkState("", "unexpected").ok, false);
  });

  // No record means the response cannot be tied to anything this browser
  // did, so it fails closed rather than passing for want of a comparison.
  it("リクエストの記録が無ければ通らない", () => {
    assert.equal(checkState(null, "af0ifjsldkj").ok, false);
  });
});
