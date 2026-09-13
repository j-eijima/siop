// The request this browser sent is accepted for one response only. Kept apart
// from the page, so the tabs can be played out with a stand-in for localStorage.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { pendingRequest } from "../public/pending.js";

const KEY = "siop-rp.pending-request";

class Storage {
  #items = new Map();
  getItem(key) { return this.#items.has(key) ? this.#items.get(key) : null; }
  setItem(key, value) { this.#items.set(key, String(value)); }
  removeItem(key) { this.#items.delete(key); }
}

const recorded = (nonce) => JSON.stringify({ nonce, state: "s", audience: "https://rp.example/cb" });

describe("待っているリクエストの受け入れ", () => {
  it("記録が無ければ受け入れない", () => {
    assert.equal(pendingRequest(new Storage(), KEY).accept(), false);
  });

  // Both tabs read the record before either has finished verifying. Only the
  // first to claim it accepts; the other is a replay, however valid.
  it("同じ記録を読んだ二つのタブのうち、受け入れるのは先の一つだけ", () => {
    const storage = new Storage();
    storage.setItem(KEY, recorded("n1"));
    const first = pendingRequest(storage, KEY);
    const second = pendingRequest(storage, KEY);

    assert.equal(first.accept(), true);
    assert.equal(second.accept(), false);
    assert.equal(storage.getItem(KEY), null);
  });

  it("受け入れたページは、描き直しても受け入れたまま", () => {
    const storage = new Storage();
    storage.setItem(KEY, recorded("n1"));
    const page = pendingRequest(storage, KEY);
    assert.equal(page.accept(), true);
    assert.equal(page.accept(), true);
  });

  it("あとから始めた新しいリクエストの記録は消さない", () => {
    const storage = new Storage();
    storage.setItem(KEY, recorded("n1"));
    const stale = pendingRequest(storage, KEY);
    storage.setItem(KEY, recorded("n2"));

    assert.equal(stale.accept(), false);
    assert.equal(storage.getItem(KEY), recorded("n2"));
  });

  it("記録した値をそのまま返す", () => {
    const storage = new Storage();
    storage.setItem(KEY, recorded("n1"));
    assert.equal(pendingRequest(storage, KEY).value.nonce, "n1");
  });
});
