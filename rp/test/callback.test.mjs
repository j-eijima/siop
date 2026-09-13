// The result page judges a response once, as it loads, and only redraws after
// that (docs/decisions/0015). A switch of language or of scenario can still
// come while the judgement waits on verification or on the lock. The page is
// run as it is, with stand-ins for the DOM, storage and locks, so those
// overlaps can be played out one step at a time.

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

import { pendingRequest } from "../public/pending.js";

const KEY = "siop-rp.pending-request";
const SPENT = "siop-rp.spent-nonces";

const source = (await readFile(new URL("../public/callback.js", import.meta.url), "utf8"))
  .replace(/^import .*;\n/gm, "");
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};
const tick = () => new Promise((done) => setImmediate(done));

/// What the verifier returns: the nonce check passing or failing, and a token
/// valid for another ten minutes.
const verified = (ok) => ({
  checks: [{ id: "nonce", ok, expected: "n", actual: "n" }],
  payload: { exp: Date.now() / 1000 + 600, sub: "subject" },
});

/// Opens the result page on `hash`. Verification and the lock are each held
/// until the test resolves them, unless `verify` answers for the verifier.
async function page({ hash = "#id_token=token&state=s", noRecord = false, verify } = {}) {
  const nodes = new Map();
  function node() {
    return { value: "normal", textContent: "", listeners: {},
      addEventListener(type, fn) { this.listeners[type] = fn; },
      removeAttribute() {}, append() {}, replaceChildren() {},
      querySelector(key) { return get(key); } };
  }
  function get(id) { if (!nodes.has(id)) nodes.set(id, node()); return nodes.get(id); }
  const events = {};
  let language;
  let reloaded = false;
  let verifications = 0;
  const location = { hash, href: `https://rp/cb${hash}`,
    reload() { reloaded = true; } };
  const items = new Map([[KEY, JSON.stringify({ nonce: "n", state: "s", audience: "a" })]]);
  if (noRecord) items.clear();
  const storage = { getItem: (k) => items.get(k) ?? null, setItem: (k, v) => items.set(k, v), removeItem: (k) => items.delete(k) };
  const verification = deferred();
  const lock = deferred();
  const locks = { request: async (_name, fn) => { await lock.promise; return fn(); } };
  const result = verified(true);
  const run = new (Object.getPrototypeOf(async function () {}).constructor)(
    "onLanguageChange", "t", "renderParams", "pendingRequest", "canonicalJWK", "checkState", "verifySelfIssuedIDToken",
    "document", "window", "location", "localStorage", "navigator", "console", source)(
    (fn) => { language = fn; }, (key) => key, () => {}, pendingRequest, () => "",
    () => ({ id: "state", ok: true, expected: "s", actual: "s" }),
    (...args) => { verifications++; return verify ? verify(...args) : verification.promise; },
    { getElementById: get, createElement: node }, { addEventListener: (key, fn) => { events[key] = fn; } },
    location, storage, { locks }, { info() {} });
  const choose = (value) => { get("scenario").value = value; get("scenario").listeners.change(); };
  return { get, events, language: () => language(), choose, run, verification, lock, result, items, location,
    verdict: () => get(".verdict").textContent,
    reloaded: () => reloaded, verifications: () => verifications };
}

describe("結果ページは一度だけ判定し、あとは描き直すだけ", () => {
  it("検証中やロック待ちに言語を切り替えても、受け入れた結果を示し続ける", async () => {
    const p = await page();
    p.language();
    p.verification.resolve(p.result);
    await tick();
    p.language();
    p.language();
    p.lock.resolve();
    await p.run;
    await tick();
    assert.equal(p.verdict(), "verdict.ok");
    // A redraw shows what was judged; it does not check the token afresh.
    p.language();
    await tick();
    assert.equal(p.verdict(), "verdict.ok");
    assert.equal(p.verifications(), 1);
  });

  // The review's bypass: a token whose nonce is the recorded one plus
  // "-changed" fails the real check and passes the changed one.
  it("記録どおりの照合に失敗した応答は、期待値を差し替えて通っても受け入れない", async () => {
    const p = await page({ verify: (_token, { nonce }) => Promise.resolve(verified(nonce === "n-changed")) });
    p.lock.resolve();
    await p.run;
    await tick();
    assert.equal(p.verdict(), "verdict.failed");
    p.choose("nonce");
    await tick();
    assert.equal(p.verdict(), "verdict.simulated");
    assert.equal(p.items.has(KEY), true);
    assert.equal(p.items.has(SPENT), false);
  });

  it("受け入れ待ちの間に期待値を差し替えても成功とは示さず、記録どおりの照合による受け入れは変わらない", async () => {
    const p = await page();
    p.verification.resolve(p.result);
    await tick();
    p.choose("nonce");
    p.lock.resolve();
    await p.run;
    await tick();
    assert.equal(p.verdict(), "verdict.simulated");
    assert.equal(p.items.has(KEY), false);
    p.choose("normal");
    await tick();
    assert.equal(p.verdict(), "verdict.ok");
  });

  // Safari hands a new response to the tab already showing one: the page
  // reloads to judge it, and the response on its way out claims nothing.
  it("フラグメントが変われば読み込み直し、まだ受け入れていない応答では受け入れない", async () => {
    for (const accepted of [false, true]) {
      const p = await page();
      p.verification.resolve(p.result);
      await tick();
      if (accepted) { p.lock.resolve(); await p.run; }
      p.location.href = "https://rp/cb#id_token=other";
      p.events.hashchange();
      p.lock.resolve();
      await p.run;
      await tick();
      assert.equal(p.reloaded(), true);
      assert.equal(p.items.has(KEY), !accepted);
    }
  });

  it("記録の無い応答や照合に失敗した応答は、描き直しが重なっても受け入れない", async () => {
    for (const options of [{ noRecord: true }, { noRecord: true, hash: "#id_token=token" }, {}]) {
      const p = await page(options);
      if (!options.noRecord) p.result.checks[0].ok = false;
      p.language();
      p.verification.resolve(p.result);
      p.lock.resolve();
      await p.run;
      await tick();
      assert.equal(p.verdict(), options.noRecord ? "verdict.noRecord" : "verdict.failed");
      assert.equal(p.items.has(SPENT), false);
      assert.equal(p.items.has(KEY), !options.noRecord);
    }
  });

  it("応答パラメータが重複していれば、検証する前に止まる", async () => {
    const p = await page({ hash: "#id_token=token&state=s&state=other" });
    await p.run;
    assert.equal(p.verdict(), "verdict.ambiguous");
    assert.equal(p.items.has(KEY), true);
    assert.equal(p.verifications(), 0);
  });
});
