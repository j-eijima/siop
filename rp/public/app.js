// Builds a Self-Issued OP authentication request (OpenID Connect Core 1.0 Section 7.3).
// Every parameter is editable so that non-conforming requests can be sent on
// purpose to see how the OP responds.

import { known, onLanguageChange, t } from "./i18n.js";
import { renderParams } from "./params-table.js";
import { httpRedirectForbidden } from "./spec-rules.js";

const STORAGE_KEY = "siop-rp.pending-request";

const redirectURI = new URL("callback.html", location.href).toString();

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/// The parameters a Self-Issued OP request is made of. `name` doubles as the
/// query parameter name and as the key for why it is there; `checked` marks
/// the ones the response will be compared against.
function defaultParameters() {
  return [
    { name: "response_type", value: "id_token", ref: "7.1 / 3.2" },
    { name: "client_id", value: redirectURI, ref: "7.2", checked: true },
    { name: "redirect_uri", value: redirectURI, ref: "3.1.2.1" },
    { name: "scope", value: "openid", ref: "3.1.2.1 / 7.1" },
    { name: "nonce", value: randomToken(), ref: "3.2.2.1", checked: true },
    { name: "state", value: randomToken(), ref: "3.1.2.1", checked: true },
  ];
}

/// Optional parameters worth trying against a Self-Issued OP.
const ADDITIONAL = {
  claims: { ref: "5.5" },
  registration: { ref: "7.2.1" },
  id_token_hint: { ref: "3.1.2.1" },
  request: { ref: "6.1" },
  prompt: { ref: "3.1.2.1" },
  max_age: { ref: "3.1.2.1" },
};

let parameters = defaultParameters();

const paramsBox = document.getElementById("params");
const expectationsBox = document.getElementById("expectations");
const requestURLBlock = document.getElementById("requestURL");
const startLink = document.getElementById("start-authentication");
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
    found.push(t("warn.responseType", { value: responseType || t("note.none") }));
  }
  if (!valueOf("scope").split(" ").includes("openid")) found.push(t("warn.scope"));
  if (!valueOf("nonce")) found.push(t("warn.nonce"));
  const clientID = valueOf("client_id");
  const redirect = valueOf("redirect_uri");
  if (redirect && clientID !== redirect) found.push(t("warn.mismatch", { clientID }));
  // Where the response will actually land: a Self-Issued OP answers to
  // client_id when redirect_uri is left out (7.2). This RP is a web page, so
  // the native-app exception never applies — not even to its own
  // http://localhost default, which is reported like any other
  // (docs/decisions/0013).
  if (httpRedirectForbidden(redirect || clientID)) found.push(t("warn.http"));
  if (clientID && clientID !== redirectURI) found.push(t("warn.elsewhere"));
  return found;
}

const whyFor = (name) => (known(`why.${name}`) ? t(`why.${name}`) : undefined);

/// Rebuilds the fields. Kept separate from `refresh` so that typing in a field
/// never tears down the input that has focus.
function renderFields() {
  renderParams(paramsBox, parameters.map((parameter, index) => ({
    ...parameter,
    why: whyFor(parameter.name),
    checked: parameter.checked ? t("badge.checked") : undefined,
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
  warningList.replaceChildren(...found.map((warning) => {
    const item = document.createElement("li");
    item.textContent = warning;
    return item;
  }));

  // What the callback will check the response against.
  const expected = {
    nonce: valueOf("nonce"),
    state: valueOf("state"),
    audience: valueOf("client_id"),
    requestURL,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(expected));
  renderParams(expectationsBox, [
    { name: "aud", value: expected.audience, why: t("expect.aud") },
    { name: "nonce", value: expected.nonce, why: t("expect.nonce") },
    { name: "state", value: expected.state, why: t("expect.state") },
  ]);

  // Section 7.3 request, spelled out for anyone reading along in the console.
  console.info("[SIOP RP] authentication request", Object.fromEntries(
    parameters.filter((p) => p.name && p.value !== "").map((p) => [p.name, p.value]),
  ));
}

function render() {
  renderFields();
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
  const button = event.currentTarget;
  try {
    await navigator.clipboard.writeText(buildRequestURL());
    button.textContent = t("button.copied");
  } catch {
    button.textContent = t("button.copyFailed");
  }
  setTimeout(() => { button.textContent = t("button.copyURL"); }, 1500);
});

onLanguageChange(render);
render();
