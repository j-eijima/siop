// The spec's rules on the request itself, which the request page reports as
// departures from the spec.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { httpRedirectForbidden } from "../public/spec-rules.js";

const native = { native: true };

describe("redirect_uri のスキーム (3.2.2.1)", () => {
  it("https は通る", () => {
    assert.equal(httpRedirectForbidden("https://rp.example/callback.html"), false);
    assert.equal(httpRedirectForbidden("https://rp.example/callback.html", native), false);
  });

  // The exception belongs to native applications. This RP is a web page,
  // so its own http://localhost default is outside it.
  it("Web のクライアントでは localhost の http も通らない", () => {
    assert.equal(httpRedirectForbidden("http://localhost:8080/callback.html"), true);
    assert.equal(httpRedirectForbidden("http://127.0.0.1:8080/callback.html"), true);
    assert.equal(httpRedirectForbidden("http://[::1]:8080/callback.html"), true);
  });

  it("ネイティブアプリなら localhost とループバックの IPv4 / IPv6 リテラルは例外として通る", () => {
    assert.equal(httpRedirectForbidden("http://localhost:8080/callback", native), false);
    assert.equal(httpRedirectForbidden("http://127.0.0.1:8080/callback", native), false);
    assert.equal(httpRedirectForbidden("http://[::1]:8080/callback", native), false);
  });

  // The exception names three hosts exactly. A loopback address it does not
  // name, or a name that only starts like one, is not in it.
  it("ネイティブアプリでも、仕様が挙げていないホストは例外に入らない", () => {
    assert.equal(httpRedirectForbidden("http://127.0.0.2/callback", native), true);
    assert.equal(httpRedirectForbidden("http://localhost.example/callback", native), true);
    assert.equal(httpRedirectForbidden("http://192.168.1.10:8080/callback", native), true);
  });

  it("http 以外のスキームはこの規則の対象外", () => {
    assert.equal(httpRedirectForbidden("com.example.app://callback"), false);
  });

  it("URL として読めない値はこの規則では判定しない", () => {
    assert.equal(httpRedirectForbidden("not a url"), false);
    assert.equal(httpRedirectForbidden(""), false);
  });
});
