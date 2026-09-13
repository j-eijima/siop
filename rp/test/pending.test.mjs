// The request this browser sent is accepted for one response only. Kept apart
// from the page, so the tabs can be played out with stand-ins for
// localStorage and navigator.locks.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { pendingRequest, writePendingRequest } from "../public/pending.js";

const KEY = "siop-rp.pending-request";

class Storage {
  #items = new Map();
  getItem(key) { return this.#items.has(key) ? this.#items.get(key) : null; }
  setItem(key, value) { this.#items.set(key, String(value)); }
  removeItem(key) { this.#items.delete(key); }
}

/// navigator.locks as the tabs of one origin see it: callbacks under one name
/// run one at a time, each after the last has finished.
class Locks {
  #tails = new Map();
  request(name, callback) {
    const previous = this.#tails.get(name) ?? Promise.resolve();
    const run = previous.then(() => callback());
    this.#tails.set(name, run.catch(() => {}));
    return run;
  }
}

const recorded = (nonce) => JSON.stringify({ nonce, state: "s", audience: "https://rp.example/cb" });

/// A token valid for another ten minutes, as the Swift OP issues them.
const NOW = 1_800_000_000;
const valid = { expiresAt: NOW + 600, now: NOW };

function withRecord(nonce = "n1") {
  const storage = new Storage();
  storage.setItem(KEY, recorded(nonce));
  return storage;
}

describe("待っているリクエストの受け入れ", () => {
  it("記録が無ければ受け入れない", async () => {
    assert.equal(await pendingRequest(new Storage(), KEY, new Locks()).accept(valid), false);
  });

  // Both tabs have read the record and claim it at the same moment. The lock
  // lets exactly one find it.
  it("二つのタブが同時に取りに行っても、受け入れるのは一つだけ", async () => {
    const storage = withRecord();
    const locks = new Locks();
    const first = pendingRequest(storage, KEY, locks);
    const second = pendingRequest(storage, KEY, locks);

    const results = await Promise.all([first.accept(valid), second.accept(valid)]);

    assert.deepEqual(results.filter(Boolean).length, 1, `受け入れたタブ: ${results}`);
    assert.equal(storage.getItem(KEY), null);
  });

  it("受け入れたページは、描き直しても受け入れたまま", async () => {
    const page = pendingRequest(withRecord(), KEY, new Locks());
    assert.equal(await page.accept(valid), true);
    assert.equal(await page.accept(valid), true);
  });

  it("あとから始めた新しいリクエストの記録は消さない", async () => {
    const storage = withRecord("n1");
    const stale = pendingRequest(storage, KEY, new Locks());
    storage.setItem(KEY, recorded("n2"));

    assert.equal(await stale.accept(valid), false);
    assert.equal(storage.getItem(KEY), recorded("n2"));
  });

  // A request page left open used to write the record back after its
  // response was accepted. The callback reopened then found it again.
  it("受け入れた後に控えが書き戻されても、同じ nonce は二度と受け入れない", async () => {
    const storage = withRecord("n1");
    const locks = new Locks();
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), true);

    storage.setItem(KEY, recorded("n1"));
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), false);
  });

  it("別の nonce の新しいリクエストは、その後も受け入れる", async () => {
    const storage = withRecord("n1");
    const locks = new Locks();
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), true);

    storage.setItem(KEY, recorded("n2"));
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), true);
  });

  // The spent list used to keep the last fifty nonces, so a long-lived token
  // could be replayed once enough others had been accepted after it.
  it("トークンが有効な間は、ほかにいくつ受け入れても、同じ nonce は受け入れない", async () => {
    const storage = withRecord("n1");
    const locks = new Locks();
    assert.equal(await pendingRequest(storage, KEY, locks).accept({ expiresAt: NOW + 86_400, now: NOW }), true);
    for (let i = 0; i < 60; i++) {
      storage.setItem(KEY, recorded(`other-${i}`));
      assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), true);
    }

    storage.setItem(KEY, recorded("n1"));
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), false);
  });

  // Once its token has expired, the token fails its own exp check, so the
  // nonce need not be remembered any longer.
  it("トークンの期限が過ぎれば、その nonce は忘れてよい", async () => {
    const storage = withRecord("n1");
    const locks = new Locks();
    assert.equal(await pendingRequest(storage, KEY, locks).accept(valid), true);

    storage.setItem(KEY, recorded("n1"));
    const later = { expiresAt: NOW + 2_000, now: NOW + 600 + 121 };
    assert.equal(await pendingRequest(storage, KEY, locks).accept(later), true);
  });

  it("期限の分からない応答は受け入れない", async () => {
    const storage = withRecord();
    assert.equal(await pendingRequest(storage, KEY, new Locks()).accept(), false);
    assert.equal(storage.getItem(KEY), recorded("n1"));
  });

  // With no way to make the claim exclusive, accepting would risk two tabs
  // both succeeding. Nothing is accepted, and the record is left alone.
  it("ロックが使えなければ受け入れず、記録にも触らない", async () => {
    const storage = withRecord();
    assert.equal(await pendingRequest(storage, KEY, undefined).accept(valid), false);
    assert.equal(storage.getItem(KEY), recorded("n1"));
  });

  it("記録した値をそのまま返す", () => {
    assert.equal(pendingRequest(withRecord("n1"), KEY, new Locks()).value.nonce, "n1");
  });
});

const SPENT = "siop-rp.spent-nonces";

/// A promise and the function that settles it, to hold a lock until the test
/// lets it go.
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};

describe("重なり合う受け入れと書き込み", () => {
  // A redraw on the same page claims again while the first claim still waits
  // for the lock another tab holds.
  it("同じページで重なった受け入れは一つの取得を分け合い、受け入れたままでいる", async () => {
    const storage = withRecord();
    const locks = new Locks();
    const gate = deferred();
    const held = locks.request(KEY, () => gate.promise);
    const page = pendingRequest(storage, KEY, locks);
    const first = page.accept(valid);
    const second = page.accept(valid);
    gate.resolve();
    await held;
    assert.deepEqual(await Promise.all([first, second]), [true, true]);
    assert.equal(page.accepted, true);
    assert.equal(await page.accept(valid), true);
  });

  it("ロックを待つ間に期待値やフラグメントが変われば、何も消費しない", async () => {
    const storage = withRecord();
    const locks = new Locks();
    const gate = deferred();
    locks.request(KEY, () => gate.promise);
    const page = pendingRequest(storage, KEY, locks);
    let current = true;
    const claim = page.accept({ ...valid, isCurrent: () => current });
    current = false;
    gate.resolve();
    assert.equal(await claim, false);
    assert.equal(storage.getItem(KEY), recorded("n1"));
    assert.equal(await page.accept(valid), true);
  });

  it("先に並んだ書き込みがあれば、古いリクエストへの受け入れは新しい記録を消費しない", async () => {
    const storage = withRecord();
    const locks = new Locks();
    const gate = deferred();
    locks.request(KEY, () => gate.promise);
    const page = pendingRequest(storage, KEY, locks);
    const write = writePendingRequest(storage, KEY, locks, JSON.parse(recorded("n2")), () => true);
    const claim = page.accept(valid);
    gate.resolve();
    assert.equal(await write, true);
    assert.equal(await claim, false);
    assert.equal(storage.getItem(KEY), recorded("n2"));
  });

  it("遅れて届いた削除の通知では、その後に書かれた新しいリクエストを上書きしない", async () => {
    const storage = withRecord();
    const locks = new Locks();
    const gate = deferred();
    locks.request(KEY, () => gate.promise);
    const write = writePendingRequest(storage, KEY, locks, JSON.parse(recorded("event")),
      () => storage.getItem(KEY) === null);
    storage.setItem(KEY, recorded("newer"));
    gate.resolve();
    assert.equal(await write, false);
    assert.equal(storage.getItem(KEY), recorded("newer"));
  });

  it("使用済みの nonce の記録が読めない・書けないときは、記録を消す前に止まる", async () => {
    for (const bad of ['{}', '[{"nonce":"n1"}]', 'broken']) {
      const storage = withRecord();
      storage.setItem(SPENT, bad);
      const page = pendingRequest(storage, KEY, new Locks());
      assert.equal(await page.accept(valid), false);
      assert.equal(page.failure, "unavailable");
      assert.equal(storage.getItem(KEY), recorded("n1"));
    }
    const storage = withRecord();
    storage.setItem = () => { throw new Error("quota"); };
    assert.equal(await pendingRequest(storage, KEY, new Locks()).accept(valid), false);
    assert.equal(storage.getItem(KEY), recorded("n1"));
  });

  it("壊れた記録、有限でない時刻、期限切れのトークンでは受け入れない", async () => {
    for (const record of ['broken', '{}', '[]', '{"nonce":""}']) {
      const storage = withRecord();
      storage.setItem(KEY, record);
      assert.equal(await pendingRequest(storage, KEY, new Locks()).accept(valid), false);
    }
    for (const times of [{ ...valid, expiresAt: Infinity }, { ...valid, now: NaN },
      { expiresAt: NOW - 120, now: NOW }]) {
      const storage = withRecord();
      assert.equal(await pendingRequest(storage, KEY, new Locks()).accept(times), false);
      assert.equal(storage.getItem(KEY), recorded("n1"));
    }
  });

  it("期限はロックを待った後で確かめる", async () => {
    const storage = withRecord();
    const gate = deferred();
    const locks = new Locks();
    locks.request(KEY, () => gate.promise);
    const originalNow = Date.now;
    try {
      Date.now = () => NOW * 1000;
      const page = pendingRequest(storage, KEY, locks);
      const claim = page.accept({ expiresAt: NOW + 10 });
      Date.now = () => (NOW + 130) * 1000;
      gate.resolve();
      assert.equal(await claim, false);
      assert.equal(page.failure, "expired");
      assert.equal(storage.getItem(KEY), recorded("n1"));
    } finally { Date.now = originalNow; }
  });

  it("記録を消せなくても使用済みの nonce は残り、ロックの拒否は理由として伝わる", async () => {
    const storage = withRecord();
    const remove = storage.removeItem.bind(storage);
    storage.removeItem = () => { throw new Error("storage denied"); };
    const page = pendingRequest(storage, KEY, new Locks());
    assert.equal(await page.accept(valid), false);
    storage.removeItem = remove;
    assert.equal(await pendingRequest(storage, KEY, new Locks()).accept(valid), false);
    const rejected = pendingRequest(withRecord(), KEY, { request: async () => { throw new Error("denied"); } });
    assert.equal(await rejected.accept(valid), false);
    assert.equal(rejected.failure, "unavailable");
  });
});
