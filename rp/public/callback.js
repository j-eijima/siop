// Receives the Self-Issued OP response from the URL fragment and verifies it
// (OpenID Connect Core 1.0 Section 7.5), laying each value this RP sent
// beside the one that came back. Nothing is sent to the server: in the
// Implicit Flow the response lives in the fragment, which browsers do not
// transmit.

import { onLanguageChange, t } from "./i18n.js";
import { renderParams } from "./params-table.js";
import { canonicalJWK, checkState, verifySelfIssuedIDToken } from "./siop-verify.js";

const STORAGE_KEY = "siop-rp.pending-request";

const RESPONSE_REFS = { id_token: "7.4", state: "3.1.2.1", error: "3.1.2.6", error_description: "3.1.2.6" };

/// The order of the comparison: what binds the response to this request
/// first, then what the token has to hold on its own.
const ORDER = ["aud", "nonce", "state", "iss", "alg", "sub_jwk", "sub", "signature", "exp", "structure"];

/// Checks whose verdict is about validity rather than about a match.
const VALIDITY = new Set(["structure", "sub_jwk", "signature", "exp"]);

const $ = (id) => document.getElementById(id);
const fragment = new URLSearchParams(location.hash.slice(1));

// Safari can hand a new response to a tab already showing this page. Only the
// fragment changes, which does not reload it, and the page reads the fragment
// once — so without this it would go on showing the previous response as if
// it were the new one.
window.addEventListener("hashchange", () => location.reload());

const pending = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null");

// One-shot: the nonce must not be reusable for a later response. It is spent
// only by the response that answers it — the one carrying the state it was
// sent with — so a stale tab or an unsolicited link cannot throw away a request
// whose real response is still on its way. The values stay in this page, so
// the response can still be re-checked below.
if (pending && fragment.has("id_token") && checkState(pending.state ?? "", fragment.get("state")).ok) {
  localStorage.removeItem(STORAGE_KEY);
}

/// What this RP expects, as it sent it. Null throughout when this browser has
/// no record of the request, which fails those comparisons rather than
/// skipping them.
const recorded = pending
  ? { audience: pending.audience, nonce: pending.nonce, state: pending.state ?? "" }
  : { audience: null, nonce: null, state: null };

/// Each replaces one expectation, so one check can be watched failing while
/// the token stays exactly as it came.
const SCENARIOS = {
  normal: (expected) => expected,
  nonce: (expected) => ({ ...expected, nonce: `${expected.nonce}-changed` }),
  state: (expected) => ({ ...expected, state: `${expected.state}-changed` }),
  aud: (expected) => ({ ...expected, audience: "https://other.example/cb" }),
};

const scenario = $("scenario");
scenario.disabled = !pending || !fragment.has("id_token");
scenario.addEventListener("change", () => evaluate());

$("copy-token").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  try {
    await navigator.clipboard.writeText(fragment.get("id_token"));
    button.textContent = t("button.copied");
  } catch {
    button.textContent = t("button.copyJWTFailed");
  }
  setTimeout(() => { button.textContent = t("button.copyJWT"); }, 2000);
});

/// A value from the verifier: a string is shown as it is — it came from the
/// request or the token — and a note is put into words.
function display(value) {
  return typeof value === "string" ? value : t(`note.${value.note}`, value);
}

function setVerdict(outcome, title, message) {
  const summary = $("summary");
  summary.className = `result-summary${outcome === "ok" ? "" : " error"}`;
  const verdict = summary.querySelector(".verdict");
  // Dropped once a verdict is in, so switching language does not put
  // "Checking…" back over it.
  verdict.removeAttribute("data-i18n");
  verdict.textContent = title;
  summary.querySelector("p").textContent = message;
}

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}

function row(check) {
  const tr = element("tr", undefined, check.ok ? "" : "fail");
  const name = element("td");
  name.append(element("code", check.id), element("small", t(`relation.${check.id}`)));
  const expected = element("td");
  expected.append(element("code", display(check.expected)));
  const actual = element("td");
  actual.append(element("code", display(check.actual)));
  const verdict = element("td");
  const mark = VALIDITY.has(check.id)
    ? t(check.ok ? "mark.valid" : "mark.invalid")
    : t(check.ok ? "mark.match" : "mark.mismatch");
  verdict.append(element("span", mark, `badge ${check.ok ? "green" : "red"}`));
  tr.append(name, expected, actual, verdict);
  return tr;
}

/// Show what was sent and what came back before judging either.
function renderExchange() {
  renderParams($("request"), pending
    ? [...new URL(pending.requestURL).searchParams].map(([name, value]) => ({ name, value }))
    : [{ name: t("note.none"), value: "", why: t("why.noRecord") }]);

  const received = [...fragment].map(([name, value]) => ({
    name, value, ref: RESPONSE_REFS[name], why: RESPONSE_REFS[name] ? t(`why.response.${name}`) : undefined,
  }));
  renderParams($("response"), received.length
    ? received
    : [{ name: t("note.none"), value: "", why: t("why.noResponse") }]);
  $("response-raw").textContent = location.href;
}

async function evaluate() {
  const expected = SCENARIOS[scenario.value](recorded);
  const body = $("comparison-body");
  $("thumbprint-raw").textContent = t("result.noToken");
  $("token-raw").textContent = t("result.noToken");

  if (fragment.has("error")) {
    // Section 3.1.2.6: the OP reports a refusal as an error response.
    setVerdict("ng", t("verdict.error"),
      `${fragment.get("error")} · ${fragment.get("error_description") ?? t("verdict.refused")}`);
    body.replaceChildren(
      row({ id: "error", expected: "id_token", actual: fragment.get("error"), ok: false }),
      row(checkState(expected.state, fragment.get("state"))),
    );
    $("result-count").textContent = t("count.noToken");
    return;
  }

  if (!fragment.has("id_token")) {
    setVerdict("ng", t("verdict.noResponse"), t("verdict.noResponseDetail"));
    body.replaceChildren();
    $("result-count").textContent = t("count.notReceived");
    return;
  }

  const idToken = fragment.get("id_token");
  const result = await verifySelfIssuedIDToken(idToken, { audience: expected.audience, nonce: expected.nonce });
  // state travels outside the token, so it is checked apart from it — and a
  // mismatch no longer hides every other check.
  const checks = [...result.checks, checkState(expected.state, fragment.get("state"))]
    .sort((a, b) => ORDER.indexOf(a.id) - ORDER.indexOf(b.id));
  console.info("[SIOP RP] checks", checks);

  const failed = checks.filter((check) => !check.ok);
  if (failed.length === 0) {
    // EndToEndRPTests waits for the English title, verdict.ok in i18n.js —
    // Safari hands XCUITest no DOM ids — so change the two together.
    setVerdict("ok", t("verdict.ok"), t("verdict.okDetail", { sub: result.payload.sub }));
  } else if (!pending) {
    // Most often this means the response landed in a different browser: iOS
    // sends an https URL to the *default* browser, and the OP has no way to
    // return to the specific browser that started the request. nonce and
    // state live in that browser's storage, so the check fails closed.
    setVerdict("ng", t("verdict.noRecord"), t("verdict.noRecordDetail"));
  } else {
    setVerdict("ng", t("verdict.failed"), t("verdict.failedDetail", { ids: failed.map((check) => check.id).join(" / ") }));
  }

  $("result-count").textContent = t("count.passed", { passed: checks.length - failed.length, total: checks.length });
  body.replaceChildren(...checks.map(row));

  if (result.thumbprint) {
    const matches = result.thumbprint === result.payload.sub;
    $("thumbprint-raw").textContent = [
      canonicalJWK(result.payload.sub_jwk),
      "", "SHA-256 → Base64url", result.thumbprint,
      "", "ID Token.sub", String(result.payload.sub),
      "", t(matches ? "mark.match" : "mark.mismatch"),
    ].join("\n");
  }
  if (result.header) {
    $("token-raw").textContent = [
      "JOSE header", JSON.stringify(result.header, null, 2),
      "", "Payload", JSON.stringify(result.payload, null, 2),
      "", "JWT", idToken,
    ].join("\n");
    $("copy-token").disabled = false;
  }
}

onLanguageChange(() => {
  renderExchange();
  evaluate();
});
renderExchange();
await evaluate();
