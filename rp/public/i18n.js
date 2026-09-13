// The RP's wording, in English and Japanese.
//
// English is the fallback, as it is the canonical language of the project.
// Otherwise the browser's preference decides, and a choice made on the page —
// or passed as ?lang=en / ?lang=ja, which is how EndToEndRPTests pins it — is
// remembered in this browser for the pages that follow.
//
// Switching redraws in place rather than reloading: the result page checks a
// one-shot record, and a reload would find it already spent.

const STORAGE_KEY = "siop-rp.lang";
const SUPPORTED = ["en", "ja"];

const MESSAGES = {
  en: {
    "page.title.request": "SIOP test RP",
    "page.title.result": "SIOP test RP — result",
    "top.note": "Verified entirely in this browser",
    "lang.label": "Language",
    "eyebrow.request": "RELYING PARTY / AUTHENTICATION REQUEST",
    "eyebrow.result": "RELYING PARTY / RESULT",
    "heading": "Match request and response, one value at a time.",
    "subtitle.request": "Check what will be sent, hand it to the SIOP, and verify the ID Token that comes back on this page.",
    "subtitle.result": "What was sent beside what came back, and the ground for each verdict. The ID Token never reaches a server; it is verified on this page.",
    "flow.label": "Progress of the authentication",
    "flow.request": "RP requests",
    "flow.sign": "Identity chosen and signed",
    "flow.check": "RP checks",
    "footer.static": "Test RP · static files only · the ID Token is never sent to a server",
    "footer.crypto": "Signatures, thumbprints and checks run on WebCrypto",

    "request.title": "Authentication request",
    "request.lede": "Everything is editable. Values outside the spec are sent as they are.",
    "badge.byRP": "Built by the RP",
    "badge.checked": "Checked in the response",
    "button.addParam": "Add parameter",
    "button.regenerate": "Regenerate nonce / state",
    "button.reset": "Defaults",
    "warnings.title": "Departures from the spec",
    "action.keep": "Values marked “Checked in the response” are kept, then compared with what comes back.",
    "action.start": "Choose an identity in SIOP →",
    "url.title": "Request to be sent",
    "button.copyURL": "Copy URL",
    "button.copied": "Copied",
    "button.copyFailed": "Cannot copy",
    "expect.title": "Values checked in the response",
    "expect.badge": "Kept in this browser",
    "expect.hint": "Kept in localStorage and removed once the callback has checked them, so a nonce never authenticates twice.",
    "browser.title": "Open this in your default browser",
    "browser.hint": "The OP only opens <code>redirect_uri</code>; it cannot pick the browser that started the request. iOS hands https to the default browser, so starting in another one means the response never comes back and the nonce / state check fails. To try it on a device, open this page at the Mac's LAN address (the default client_id / redirect_uri come from the URL you opened).",

    "why.response_type": "A SIOP supports only id_token (Implicit Flow).",
    "why.client_id": "A SIOP has no registration, so the RP uses its redirect URI as the client_id. Compared with the ID Token's aud.",
    "why.redirect_uri": "Must equal client_id. The response comes back in this URL's fragment.",
    "why.scope": "Must include openid. profile, email, address and phone can be requested too.",
    "why.nonce": "Required in the Implicit Flow. Compared with the ID Token's nonce claim to stop replays.",
    "why.state": "Optional. Compared with the state in the response fragment, to confirm the response answers a request this browser made.",
    "why.claims": "Requests claims in detail, as JSON.",
    "why.registration": "Embeds the RP's metadata in the request itself.",
    "why.id_token_hint": "Presents an earlier ID Token to ask for the same identifier.",
    "why.request": "Passes the whole request as a signed JWT (Request Object).",
    "why.prompt": "Asks for re-authentication or consent.",
    "why.max_age": "Seconds allowed since the user last authenticated.",

    "warn.responseType": "response_type is \"{value}\". A SIOP supports only id_token (7.1).",
    "warn.scope": "scope does not include openid (3.1.2.1).",
    "warn.nonce": "No nonce. It is required in the Implicit Flow (3.2.2.1).",
    "warn.mismatch": "client_id and redirect_uri differ (7.2). The ID Token's aud will carry client_id \"{clientID}\".",
    "warn.elsewhere": "client_id is not this page's callback, so the response will not come back here.",
    "warn.http": "redirect_uri uses http (3.2.2.1). The Implicit Flow requires https; http is allowed only to a native app on localhost or a loopback address, and this RP is a web page. Host it on https to test within the spec.",
    "warn.unrecorded": "This request could not be recorded in this browser (that needs localStorage and the Web Locks API), so no response to it could be accepted. It cannot be started.",

    "expect.aud": "From client_id. Must equal the ID Token's aud.",
    "expect.nonce": "From nonce. Must equal the ID Token's nonce.",
    "expect.state": "From state. Must equal the state in the response fragment, outside the token.",

    "field.name": "Parameter name",
    "field.value": "Value",
    "field.remove": "Remove",

    "result.checking": "Checking…",
    "result.title": "Parameters and checks",
    "result.head.parameter": "Parameter / meaning",
    "result.head.expected": "Sent / expected",
    "result.head.actual": "Received",
    "result.head.verdict": "Verdict",
    "result.derivation": "How the public key becomes sub",
    "result.derivationSteps": "The public key's <code>e / kty / n</code> as canonical JSON<br>↓ UTF-8 → SHA-256 → Base64url<br>↓ compared with the ID Token's <code>sub</code>",
    "result.noToken": "No ID Token received.",
    "result.token": "The ID Token · header / payload / JWT",
    "button.copyJWT": "Copy JWT",
    "button.copyJWTFailed": "Cannot copy. Select the JWT shown instead",
    "result.response": "The response URL · fragment",
    "sent.title": "Request sent",
    "sent.lede": "As this browser kept it",
    "sent.again": "Make a new request",
    "scenario.title": "Watch a check fail",
    "scenario.hint": "The token stays as it came; only what this RP expects is swapped, to see how the verdicts change.",
    "scenario.label": "Expectations to check against",
    "scenario.normal": "Check against what was kept",
    "scenario.nonce": "Expect a different nonce",
    "scenario.state": "Expect a different state",
    "scenario.aud": "Expect a different RP as aud",

    "why.response.id_token": "The self-issued ID Token, signed with the key in its own sub_jwk.",
    "why.response.state": "The state sent with the request, returned as it was. Compared to prevent CSRF.",
    "why.response.error": "The OP refused the request.",
    "why.response.error_description": "An optional, human-readable reason for the refusal.",
    "why.noRecord": "No request started from this browser is on record.",
    "why.noResponse": "The fragment carries no response.",

    "relation.aud": "request.client_id → ID Token.aud",
    "relation.nonce": "request.nonce → ID Token.nonce",
    "relation.state": "request.state → fragment.state",
    "relation.iss": "Self-issued issuer (7.5)",
    "relation.alg": "JOSE header / signing algorithm (7.1)",
    "relation.sub_jwk": "The key to verify with (7.5)",
    "relation.sub": "sub_jwk → thumbprint → sub (7.5)",
    "relation.signature": "Signature checked with sub_jwk (7.5)",
    "relation.exp": "Expiry, at the time of checking",
    "relation.structure": "JWS Compact Serialization",
    "relation.error": "The OP refused the request (3.1.2.6)",

    "note.none": "(none)",
    "note.notCompared": "(not compared)",
    "note.noRecord": "(no record of the request)",
    "note.omitted": "(omitted)",
    "note.jws": "header.payload.signature",
    "note.segments": "{count} segments",
    "note.undecodable": "Cannot be decoded",
    "note.rsaKey": "RSA public key",
    "note.rsaKeyMembers": "RSA public key (kty / n / e)",
    "note.notRsaKey": "Not readable as an RSA public key",
    "note.noKeyToDerive": "(no sub_jwk to derive it from)",
    "note.validSignature": "Valid signature",
    "note.invalidSignature": "Signature does not match",
    "note.unverifiable": "Cannot be verified: {reason}",
    "note.badKeyOrAlg": "Key or alg invalid, so it cannot be verified",
    "note.after": "After {time} (allowing {skew} s)",

    "mark.valid": "✓ Valid",
    "mark.invalid": "× Invalid",
    "mark.match": "✓ Match",
    "mark.mismatch": "× Mismatch",

    "verdict.error": "Error response received",
    "verdict.refused": "The OP refused the request.",
    "verdict.noResponse": "No response",
    "verdict.noResponseDetail": "The URL fragment carries no id_token. Start from index.html.",
    "verdict.ok": "✓ Authentication verified",
    "verdict.okDetail": "Authenticated as sub = {sub}.",
    "verdict.noRecord": "× No record of the request",
    "verdict.noRecordDetail": "No request from this browser was found, so aud, nonce and state cannot be checked. This also happens when the browser that started the request and the one the response came back to (iOS's default browser) differ.",
    "verdict.replayed": "× Already answered",
    "verdict.replayedDetail": "Another response to this request has already been accepted, in another tab. This one is not: a request authenticates once, however valid a second response is.",
    "verdict.simulated": "× Not an authentication",
    "verdict.simulatedDetail": "Every check passes, but against an expectation changed on this page, not the one this RP sent. Only a response to the request as sent can authenticate.",
    "verdict.ambiguous": "× Ambiguous response",
    "verdict.ambiguousDetail": "The fragment repeats a response parameter. No request was claimed.",
    "verdict.unavailable": "× Cannot safely accept this response",
    "verdict.unavailableDetail": "The request or replay protection could not be read or saved safely. Start a new request with browser storage and Web Locks available.",
    "verdict.expired": "× Response expired",
    "verdict.expiredDetail": "The token expired while waiting to claim the request. Start a new request.",
    "verdict.noLocks": "× Cannot be accepted in this browser",
    "verdict.noLocksDetail": "This browser offers no way to make sure only one tab accepts a response (the Web Locks API), so none is accepted.",
    "verdict.failed": "× Authentication not verified",
    "verdict.failedDetail": "{ids} did not pass. This response authenticates no one.",
    "count.noToken": "No token",
    "count.notReceived": "Not received",
    "count.passed": "{passed} / {total} passed",
  },

  ja: {
    "page.title.request": "SIOP テスト RP",
    "page.title.result": "SIOP テスト RP — 検証結果",
    "top.note": "検証はこのブラウザ内で完結",
    "lang.label": "表示言語",
    "eyebrow.request": "RELYING PARTY / 認証リクエスト",
    "eyebrow.result": "RELYING PARTY / 検証結果",
    "heading": "要求と応答を、ひとつずつ照合。",
    "subtitle.request": "送る値を確かめてから SIOP に渡し、返ってきた ID Token をこのページで検証します。",
    "subtitle.result": "送った値と返ってきた値、検証の根拠を横に並べます。ID Token はサーバに送らず、このページ内で検証します。",
    "flow.label": "認証の進行状況",
    "flow.request": "RP が要求",
    "flow.sign": "識別子を選択・署名",
    "flow.check": "RP が照合",
    "footer.static": "テスト RP · 静的ファイルのみ · ID Token はサーバに送られません",
    "footer.crypto": "署名・サムプリント・照合は WebCrypto で実行",

    "request.title": "認証リクエスト",
    "request.lede": "すべて編集できます。仕様から外れた値もそのまま送れます",
    "badge.byRP": "RP が生成",
    "badge.checked": "応答と照合",
    "button.addParam": "パラメータを追加",
    "button.regenerate": "nonce / state を再生成",
    "button.reset": "既定値",
    "warnings.title": "仕様との差分",
    "action.keep": "「応答と照合」の値を控え、戻ってきた応答と突き合わせます。",
    "action.start": "SIOP で識別子を選択 →",
    "url.title": "送信する認証リクエスト",
    "button.copyURL": "URL をコピー",
    "button.copied": "コピーしました",
    "button.copyFailed": "コピーできません",
    "expect.title": "応答と照合する値",
    "expect.badge": "このブラウザに控える",
    "expect.hint": "localStorage に控え、コールバックで照合したら消します。同じ nonce で二度は認証しません。",
    "browser.title": "既定のブラウザで開いてください",
    "browser.hint": "OP は <code>redirect_uri</code> を開くだけで、リクエストを始めたブラウザを指定できません。iOS は https を既定ブラウザに渡すため、別のブラウザで始めると応答が戻らず、nonce / state の照合に失敗します。実機で試す場合は Mac の LAN アドレスでこのページを開いてください(client_id / redirect_uri の既定値は開いている URL から作られます)。",

    "why.response_type": "SIOP が対応する response_type は id_token のみ(Implicit Flow)。",
    "why.client_id": "SIOP には登録手続きが無いため、RP は redirect URI をそのまま client_id として使う。ID Token の aud と照合する。",
    "why.redirect_uri": "client_id と同じ値である必要がある。応答はこの URL のフラグメントで返る。",
    "why.scope": "openid を含める必要がある。profile・email・address・phone も要求できる。",
    "why.nonce": "Implicit Flow では必須。ID Token の nonce クレームと照合してリプレイを防ぐ。",
    "why.state": "任意。応答 fragment の state と照合して、このブラウザが始めたリクエストへの応答か確かめる。",
    "why.claims": "要求するクレームを JSON で細かく指定する。",
    "why.registration": "RP のメタデータをリクエストに直接埋め込む。",
    "why.id_token_hint": "以前発行された ID Token を提示して同じ識別子を求める。",
    "why.request": "リクエスト全体を署名付き JWT (Request Object) として渡す。",
    "why.prompt": "再認証や同意の要否を指示する。",
    "why.max_age": "認証からの許容経過秒数。",

    "warn.responseType": "response_type が \"{value}\" です。SIOP は id_token のみ対応します (7.1)。",
    "warn.scope": "scope に openid が含まれていません (3.1.2.1)。",
    "warn.nonce": "nonce がありません。Implicit Flow では必須です (3.2.2.1)。",
    "warn.mismatch": "client_id と redirect_uri が異なります (7.2)。ID Token の aud には client_id \"{clientID}\" が入ります。",
    "warn.elsewhere": "client_id がこのページのコールバックと異なるため、応答はここには戻りません。",
    "warn.http": "redirect_uri が http です (3.2.2.1)。Implicit Flow では https が必要で、http が許されるのはネイティブアプリが localhost・ループバックアドレスを使う場合だけです。この RP は Web ページなので当てはまりません。仕様どおりに試すには https でホストしてください。",
    "warn.unrecorded": "このリクエストをこのブラウザに記録できませんでした(localStorage と Web Locks API が必要です)。応答を受け入れられないので、開始できません。",

    "expect.aud": "client_id から。ID Token の aud と一致する必要がある。",
    "expect.nonce": "nonce から。ID Token の nonce と一致する必要がある。",
    "expect.state": "state から。トークンの外側、応答 fragment の state と一致する必要がある。",

    "field.name": "パラメータ名",
    "field.value": "値",
    "field.remove": "削除",

    "result.checking": "照合しています…",
    "result.title": "パラメータの対応と検証",
    "result.head.parameter": "パラメータ / 意味",
    "result.head.expected": "送信値・期待値",
    "result.head.actual": "実際の応答値",
    "result.head.verdict": "判定",
    "result.derivation": "公開鍵 → sub の導出を見る",
    "result.derivationSteps": "公開鍵の <code>e / kty / n</code> を正規化した JSON<br>↓ UTF-8 → SHA-256 → Base64url<br>↓ ID Token の <code>sub</code> と照合",
    "result.noToken": "ID Token を受け取っていません。",
    "result.token": "実際の ID Token · ヘッダ / ペイロード / JWT",
    "button.copyJWT": "JWT をコピー",
    "button.copyJWTFailed": "コピーできません。表示された JWT を選択してください",
    "result.response": "応答 URL · fragment を見る",
    "sent.title": "送信したリクエスト",
    "sent.lede": "このブラウザが控えた値",
    "sent.again": "新しいリクエストを作る",
    "scenario.title": "照合の違いを試す",
    "scenario.hint": "受け取ったトークンはそのままに、この RP が照合に使う期待値だけを差し替えて、判定がどう変わるかを見ます。",
    "scenario.label": "照合に使う期待値",
    "scenario.normal": "控えた期待値のまま照合",
    "scenario.nonce": "期待する nonce を別の値にする",
    "scenario.state": "期待する state を別の値にする",
    "scenario.aud": "期待する aud を別の RP にする",

    "why.response.id_token": "自己発行された ID Token。sub_jwk に含まれる鍵で自己署名されている。",
    "why.response.state": "リクエストで送った state がそのまま返る。照合して CSRF を防ぐ。",
    "why.response.error": "OP がリクエストを拒否したことを示す。",
    "why.response.error_description": "拒否の理由を人間向けに説明する任意の文字列。",
    "why.noRecord": "このブラウザから開始したリクエストの記録がありません。",
    "why.noResponse": "フラグメントに応答が含まれていません。",

    "relation.iss": "自己発行の issuer (7.5)",
    "relation.alg": "JOSE ヘッダ / 署名アルゴリズム (7.1)",
    "relation.sub_jwk": "検証に使う鍵 (7.5)",
    "relation.sub": "sub_jwk → サムプリント → sub (7.5)",
    "relation.signature": "sub_jwk で署名を検証 (7.5)",
    "relation.exp": "検証した時点での有効期限",
    "relation.error": "OP がリクエストを拒否 (3.1.2.6)",

    "note.none": "(なし)",
    "note.notCompared": "(照合しない)",
    "note.noRecord": "(リクエストの記録なし)",
    "note.omitted": "(省略)",
    "note.jws": "ヘッダ.ペイロード.署名",
    "note.segments": "{count} セグメント",
    "note.undecodable": "デコードできない",
    "note.rsaKey": "RSA 公開鍵",
    "note.rsaKeyMembers": "RSA 公開鍵 (kty / n / e)",
    "note.notRsaKey": "RSA 公開鍵として読めない",
    "note.noKeyToDerive": "(sub_jwk が無く算出できない)",
    "note.validSignature": "署名が有効",
    "note.invalidSignature": "署名が一致しない",
    "note.unverifiable": "検証できない: {reason}",
    "note.badKeyOrAlg": "鍵または alg が不正で検証できない",
    "note.after": "{time} より後 (許容 {skew} 秒)",

    "mark.valid": "✓ 有効",
    "mark.invalid": "× 無効",
    "mark.match": "✓ 一致",
    "mark.mismatch": "× 不一致",

    "verdict.error": "エラー応答を受信",
    "verdict.refused": "OP がリクエストを拒否しました。",
    "verdict.noResponse": "応答がありません",
    "verdict.noResponseDetail": "URL のフラグメントに id_token がありません。index.html から認証を開始してください。",
    "verdict.ok": "✓ 認証の検証に成功",
    "verdict.okDetail": "sub = {sub} として認証しました。",
    "verdict.noRecord": "× リクエストの記録がありません",
    "verdict.noRecordDetail": "このブラウザから開始したリクエストが見つからないため、aud・nonce・state を照合できません。認証を始めたブラウザと、応答が返ってきたブラウザ(iOS の既定ブラウザ)が異なる場合にも起きます。",
    "verdict.replayed": "× 応答済み",
    "verdict.replayedDetail": "このリクエストへの応答は、別のタブですでに受け入れられています。この応答は受け入れません — 二つ目の応答がどれほど正しくても、一つのリクエストで認証するのは一度だけです。",
    "verdict.simulated": "× 認証ではありません",
    "verdict.simulatedDetail": "すべての検査に通っていますが、照合したのはこのページで差し替えた期待値で、この RP が送った値ではありません。認証になるのは、送ったとおりのリクエストへの応答だけです。",
    "verdict.ambiguous": "× 応答が曖昧です",
    "verdict.ambiguousDetail": "フラグメントに応答パラメータが重複しています。リクエストは受け入れていません。",
    "verdict.unavailable": "× 応答を安全に受け入れられません",
    "verdict.unavailableDetail": "リクエストまたは再利用防止の記録を安全に読み書きできませんでした。ブラウザのストレージと Web Locks が利用できる状態で、新しいリクエストを開始してください。",
    "verdict.expired": "× 応答の有効期限切れ",
    "verdict.expiredDetail": "リクエストの受け入れを待つ間にトークンの期限が切れました。新しいリクエストを開始してください。",
    "verdict.noLocks": "× このブラウザでは受け入れられません",
    "verdict.noLocksDetail": "このブラウザには、応答を受け入れるタブが一つだけだと保証する手段(Web Locks API)が無いため、どの応答も受け入れません。",
    "verdict.failed": "× 認証の検証に失敗",
    "verdict.failedDetail": "{ids} が通りません。この応答では認証しません。",
    "count.noToken": "トークンなし",
    "count.notReceived": "未受信",
    "count.passed": "{passed} / {total} 成功",
  },
};

function stored() {
  try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
}

function remember(language) {
  try { localStorage.setItem(STORAGE_KEY, language); } catch { /* private mode: the choice lasts this page */ }
}

function choose() {
  const asked = new URLSearchParams(location.search).get("lang");
  if (SUPPORTED.includes(asked)) {
    remember(asked);
    return asked;
  }
  const kept = stored();
  if (SUPPORTED.includes(kept)) return kept;
  for (const tag of navigator.languages ?? [navigator.language]) {
    const primary = String(tag).toLowerCase().split("-")[0];
    if (SUPPORTED.includes(primary)) return primary;
  }
  return "en";
}

let language = choose();
const listeners = [];

/// The message for `key` in the current language, falling back to English and
/// then to the key itself, with `{name}` filled from `vars`.
export function t(key, vars = {}) {
  const template = MESSAGES[language][key] ?? MESSAGES.en[key] ?? key;
  return template.replace(/\{(\w+)\}/g, (match, name) => (name in vars ? String(vars[name]) : match));
}

/// Whether there is a message for `key`, so that optional wording — the
/// reason for a parameter someone typed in — can be left out when there is none.
export function known(key) {
  return key in MESSAGES.en;
}

/// Called after the language changes, to redraw what the page built itself.
export function onLanguageChange(listener) {
  listeners.push(listener);
}

/// Static text carries its key in data-i18n (plain text) or data-i18n-html
/// (markup from this file only — never from a request or a response).
function translatePage() {
  document.documentElement.lang = language;
  for (const node of document.querySelectorAll("[data-i18n]")) node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-html]")) node.innerHTML = t(node.dataset.i18nHtml);
  for (const node of document.querySelectorAll("[data-i18n-label]")) node.setAttribute("aria-label", t(node.dataset.i18nLabel));
  for (const button of document.querySelectorAll("[data-lang]")) {
    button.setAttribute("aria-pressed", String(button.dataset.lang === language));
  }
}

for (const button of document.querySelectorAll("[data-lang]")) {
  button.addEventListener("click", () => {
    const next = button.dataset.lang;
    if (!SUPPORTED.includes(next) || next === language) return;
    language = next;
    remember(next);
    translatePage();
    for (const listener of listeners) listener(next);
  });
}

translatePage();
