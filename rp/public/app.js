// Builds a Self-Issued OP authentication request (OpenID Connect Core 1.0 Section 7.3).
// Every parameter is editable so that non-conforming requests can be sent on
// purpose to see how the OP responds.

import { renderParams } from "./params-table.js";

const STORAGE_KEY = "siop-rp.pending-request";

const redirectURI = new URL("callback.html", location.href).toString();

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/// The parameters a Self-Issued OP request is made of, with the reason each
/// one is present. `name` doubles as the query parameter name.
function defaultParameters() {
  return [
    { name: "response_type", value: "id_token", ref: "7.1 / 3.2",
      why: "SIOP が対応する response_type は id_token のみ(Implicit Flow)。" },
    { name: "client_id", value: redirectURI, ref: "7.2",
      why: "SIOP には登録手続きが無いため、RP は redirect URI をそのまま client_id として使う。" },
    { name: "redirect_uri", value: redirectURI, ref: "3.1.2.1",
      why: "client_id と同じ値である必要がある。応答はこの URL のフラグメントで返る。" },
    { name: "scope", value: "openid", ref: "3.1.2.1 / 7.1",
      why: "openid を含める必要がある。profile・email・address・phone も要求できる。" },
    { name: "nonce", value: randomToken(), ref: "3.2.2.1",
      why: "Implicit Flow では必須。ID Token の nonce クレームと照合してリプレイを防ぐ。" },
    { name: "state", value: randomToken(), ref: "3.1.2.1",
      why: "任意。応答の state と照合して、このブラウザが始めたリクエストへの応答か確かめる。" },
  ];
}

/// Optional parameters worth trying against a Self-Issued OP.
const ADDITIONAL = {
  claims: { ref: "5.5", why: "要求するクレームを JSON で細かく指定する。" },
  registration: { ref: "7.2.1", why: "RP のメタデータをリクエストに直接埋め込む。" },
  id_token_hint: { ref: "3.1.2.1", why: "以前発行された ID Token を提示して同じ識別子を求める。" },
  request: { ref: "6.1", why: "リクエスト全体を署名付き JWT (Request Object) として渡す。" },
  prompt: { ref: "3.1.2.1", why: "再認証や同意の要否を指示する。" },
  max_age: { ref: "3.1.2.1", why: "認証からの許容経過秒数。" },
};

let parameters = defaultParameters();

const paramsTable = document.getElementById("params");
const requestURLBlock = document.getElementById("requestURL");
const startLink = document.getElementById("startLink");
const warningsBox = document.getElementById("warnings");
const warningList = document.getElementById("warningList");

function buildRequestURL() {
  const query = new URLSearchParams();
  for (const { name, value } of parameters) {
    if (name && value !== "") query.append(name, value);
  }
  // Section 7.1: the authorization endpoint of a Self-Issued OP is `openid:`.
  return `openid://?${query}`;
}

function valueOf(name) {
  return parameters.find((parameter) => parameter.name === name)?.value ?? "";
}

/// Deviations are reported, not blocked — sending them is the point.
function warnings() {
  const found = [];
  const responseType = valueOf("response_type");
  if (responseType !== "id_token") {
    found.push(`response_type が "${responseType || "(なし)"}" です。SIOP は id_token のみ対応します (7.1)。`);
  }
  if (!valueOf("scope").split(" ").includes("openid")) {
    found.push("scope に openid が含まれていません (3.1.2.1)。");
  }
  if (!valueOf("nonce")) {
    found.push("nonce がありません。Implicit Flow では必須です (3.2.2.1)。");
  }
  const clientID = valueOf("client_id");
  const redirect = valueOf("redirect_uri");
  if (redirect && clientID !== redirect) {
    found.push(`client_id と redirect_uri が異なります (7.2)。ID Token の aud には client_id "${clientID}" が入ります。`);
  }
  if (clientID && clientID !== redirectURI) {
    found.push("client_id がこのページのコールバックと異なるため、応答はここには戻りません。");
  }
  return found;
}

/// Rebuilds the table. Kept separate from `refresh` so that typing in a field
/// never tears down the input that has focus.
function renderTable() {
  renderParams(paramsTable, parameters.map((parameter, index) => ({
    ...parameter,
    // Only added parameters get an editable name; the required ones are fixed.
    onNameChange: parameter.removable
      ? (next) => { parameters[index].name = next; refresh(); }
      : undefined,
    onValueChange: (next) => { parameters[index].value = next; refresh(); },
    onRemove: parameter.removable
      ? () => { parameters.splice(index, 1); render(); }
      : undefined,
  })));
}

function refresh() {
  const requestURL = buildRequestURL();
  requestURLBlock.textContent = requestURL.replace(/&/g, "\n&");
  startLink.href = requestURL;

  const found = warnings();
  warningsBox.hidden = found.length === 0;
  warningList.innerHTML = "";
  for (const warning of found) {
    const item = document.createElement("li");
    const mark = document.createElement("span");
    mark.className = "mark ng";
    mark.textContent = "!";
    const text = document.createElement("div");
    text.className = "check-detail";
    text.textContent = warning;
    item.append(mark, text);
    warningList.append(item);
  }

  // What the callback will check the response against.
  localStorage.setItem(STORAGE_KEY, JSON.stringify({
    nonce: valueOf("nonce"),
    state: valueOf("state"),
    audience: valueOf("client_id"),
    requestURL,
  }));

  // Section 7.3 request, spelled out for anyone reading along in the console.
  console.info("[SIOP RP] 認証リクエスト", Object.fromEntries(
    parameters.filter((p) => p.name && p.value !== "").map((p) => [p.name, p.value]),
  ));
}

function render() {
  renderTable();
  refresh();
}

document.getElementById("regenerate").addEventListener("click", () => {
  for (const parameter of parameters) {
    if (parameter.name === "nonce" || parameter.name === "state") parameter.value = randomToken();
  }
  render();
});

document.getElementById("reset").addEventListener("click", () => {
  parameters = defaultParameters();
  render();
});

document.getElementById("addParam").addEventListener("click", () => {
  const unused = Object.keys(ADDITIONAL).find((name) => !parameters.some((p) => p.name === name));
  const name = unused ?? "";
  parameters.push({ name, value: "", removable: true, ...(ADDITIONAL[name] ?? {}) });
  render();
});

document.getElementById("copy").addEventListener("click", async (event) => {
  await navigator.clipboard.writeText(buildRequestURL());
  const button = event.currentTarget;
  button.textContent = "コピーしました";
  setTimeout(() => { button.textContent = "URL をコピー"; }, 1500);
});

render();
