// Receives the Self-Issued OP response from the URL fragment and verifies it
// (OpenID Connect Core 1.0 Section 7.5). Nothing is sent to the server: in the
// Implicit Flow the response lives in the fragment, which browsers do not
// transmit.

import { renderParams } from "./params-table.js";
import { verifySelfIssuedIDToken } from "./siop-verify.js";

const STORAGE_KEY = "siop-rp.pending-request";

const RESPONSE_PARAMS = {
  id_token: { ref: "7.4", why: "自己発行された ID Token。sub_jwk に含まれる鍵で自己署名されている。" },
  state: { ref: "3.1.2.1", why: "リクエストで送った state がそのまま返る。照合して CSRF を防ぐ。" },
  error: { ref: "3.1.2.6", why: "OP がリクエストを拒否したことを示す。" },
  error_description: { ref: "3.1.2.6", why: "拒否の理由を人間向けに説明する任意の文字列。" },
};

const CLAIMS = {
  iss: { ref: "7.4", why: "自己発行の ID Token では常に https://self-issued.me。" },
  sub: { ref: "7.4", why: "sub_jwk の JWK サムプリント (RFC 7638)。鍵と識別子を結びつける。" },
  sub_jwk: { ref: "7.4", why: "この ID Token を検証するための公開鍵。OP の鍵はここにしか無い。" },
  aud: { ref: "3.1.3.7", why: "宛先の RP。SIOP では client_id、つまり redirect URI が入る。" },
  nonce: { ref: "3.2.2.11", why: "リクエストで送った nonce。応答をそのリクエストに束縛する。" },
  iat: { ref: "2", why: "発行時刻 (UNIX 秒)。" },
  exp: { ref: "2", why: "有効期限 (UNIX 秒)。これを過ぎたトークンは受け付けない。" },
};

const summary = document.getElementById("summary");
const details = document.getElementById("details");

function showVerdict(ok, title, message) {
  summary.innerHTML = "";
  const heading = document.createElement("p");
  heading.className = `verdict ${ok ? "ok" : "ng"}`;
  heading.textContent = title;
  const body = document.createElement("p");
  body.className = "note";
  body.textContent = message;
  summary.append(heading, body);
}

const fragment = new URLSearchParams(location.hash.slice(1));
const pending = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null");

// Show what was sent and what came back before judging either.
renderParams(document.getElementById("request"), pending
  ? [...new URL(pending.requestURL).searchParams].map(([name, value]) => ({ name, value }))
  : [{ name: "(なし)", value: "", why: "このブラウザから開始したリクエストの記録がありません。" }]);

const received = [...fragment].map(([name, value]) => ({ name, value, ...(RESPONSE_PARAMS[name] ?? {}) }));
renderParams(document.getElementById("response"), received.length
  ? received
  : [{ name: "(なし)", value: "", why: "フラグメントに応答が含まれていません。" }]);

console.info("[SIOP RP] 受信した応答", Object.fromEntries(fragment));

if (fragment.has("error")) {
  // Section 3.1.2.6: the OP reports a refusal as an error response.
  showVerdict(false, `エラー応答: ${fragment.get("error")}`,
    fragment.get("error_description") ?? "OP がリクエストを拒否しました。");
} else if (!fragment.has("id_token")) {
  showVerdict(false, "応答がありません",
    "URL のフラグメントに id_token がありません。index.html から認証を開始してください。");
} else if (!pending) {
  // Most often this means the response landed in a different browser: iOS
  // sends an https URL to the *default* browser, and the OP has no way to
  // return to the specific browser that started the request. nonce and state
  // live in that browser's storage, so the check fails closed.
  showVerdict(false, "リクエストの記録がありません",
    "このブラウザから開始したリクエストが見つかりません。"
    + "認証を始めたブラウザと、応答が返ってきたブラウザ(iOS の既定ブラウザ)が"
    + "異なる場合にも起きます。既定のブラウザで index.html を開き直してください。");
} else if (fragment.get("state") !== pending.state) {
  showVerdict(false, "state が一致しません",
    `受信: ${fragment.get("state") || "(なし)"} / 期待値: ${pending.state || "(なし)"}`);
} else {
  const result = await verifySelfIssuedIDToken(fragment.get("id_token"), {
    audience: pending.audience,
    nonce: pending.nonce,
  });
  console.info("[SIOP RP] 検証結果", result);

  showVerdict(result.ok,
    result.ok ? "検証に成功しました" : "検証に失敗しました",
    result.ok
      ? `sub = ${result.payload.sub} として認証しました。`
      : "失敗した検証項目を確認してください。");

  const list = document.getElementById("checks");
  for (const check of result.checks) {
    const item = document.createElement("li");
    const mark = document.createElement("span");
    mark.className = `mark ${check.ok ? "ok" : "ng"}`;
    mark.textContent = check.ok ? "✓" : "✕";
    const text = document.createElement("div");
    const title = document.createElement("div");
    title.className = "check-title";
    title.textContent = check.title;
    const detail = document.createElement("div");
    detail.className = "check-detail";
    detail.textContent = check.detail;
    text.append(title, detail);
    item.append(mark, text);
    list.append(item);
  }

  renderParams(document.getElementById("claims"), Object.entries(result.payload).map(([name, value]) => ({
    name,
    value: typeof value === "object" ? JSON.stringify(value) : String(value),
    ...(CLAIMS[name] ?? {}),
  })));

  document.getElementById("header").textContent = JSON.stringify(result.header, null, 2);
  document.getElementById("payload").textContent = JSON.stringify(result.payload, null, 2);
  details.hidden = false;

  // One-shot: the nonce must not be reusable for a later response.
  localStorage.removeItem(STORAGE_KEY);
}
