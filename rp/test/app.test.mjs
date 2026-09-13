// The request page writes the record of the request it offers. The page is
// run as it is, with stand-ins for the DOM, storage and locks, so its writes
// can be held back and released one at a time.

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

import { writePendingRequest } from "../public/pending.js";

const KEY = "siop-rp.pending-request";

const source = (await readFile(new URL("../public/app.js", import.meta.url), "utf8"))
  .replace(/^import .*;\n/gm, "");
const tick = () => new Promise((done) => setImmediate(done));

describe("リクエストページの記録", () => {
  it("言語の切り替えや同じ値での描き直しでは書き戻さず、遅れた削除の通知で新しいリクエストを上書きしない", async () => {
    const nodes = new Map();
    function get(id) {
      if (!nodes.has(id)) nodes.set(id, { listeners: {}, append() {}, replaceChildren() {},
        removeAttribute(key) { delete this[key]; },
        addEventListener(key, fn) { this.listeners[key] = fn; } });
      return nodes.get(id);
    }
    let language;
    const events = {};
    let fields;
    const items = new Map();
    let writes = 0;
    const storage = { getItem: (k) => items.get(k) ?? null,
      setItem: (k, v) => { writes++; items.set(k, v); } };
    // Each lock request waits in `queue` until the test runs it.
    const queue = [];
    const locks = { request: (_key, fn) => new Promise((resolve) => queue.push(() => resolve(fn()))) };
    let random = 0;
    new Function("known", "onLanguageChange", "t", "renderParams", "httpRedirectForbidden", "writePendingRequest",
      "document", "window", "location", "crypto", "localStorage", "navigator", "console", source)(
      () => false, (fn) => { language = fn; }, (key) => key,
      (box, values) => { if (box === get("params")) fields = values; }, () => false, writePendingRequest,
      { getElementById: get, createElement: () => ({}) }, { addEventListener: (key, fn) => { events[key] = fn; } },
      { href: "https://rp/index.html" }, { getRandomValues: (bytes) => bytes.fill(++random) }, storage,
      { locks }, { info() {} });
    language();
    assert.equal(queue.length, 1);
    queue.shift()();
    await tick();
    // The result page in another tab accepts a response and removes the record.
    const oldValue = storage.getItem(KEY);
    items.delete(KEY);
    language();
    assert.equal(writes, 1);
    // A same-value field event must not bring the spent record back either.
    fields[0].onValueChange(fields[0].value);
    assert.equal(queue.length, 0);
    events.storage({ key: KEY, oldValue, newValue: null, storageArea: storage });
    assert.equal(queue.length, 1);
    items.set(KEY, "newer request from another tab");
    queue.shift()();
    await tick();
    assert.equal(storage.getItem(KEY), "newer request from another tab");
    assert.equal(get("start-authentication").href, undefined);
  });
});
