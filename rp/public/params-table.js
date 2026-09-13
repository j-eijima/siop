// Renders parameters as labelled fields: the value, the section it comes
// from, and why it is there. The point of this RP is to make each protocol
// field visible. Fields can be read-only (a received response) or editable
// (the outgoing request).

import { t } from "./i18n.js";

export function renderParams(container, rows) {
  container.replaceChildren(...rows.map(buildField));
}

function buildField(row) {
  const field = document.createElement("div");
  field.className = "field";

  const head = document.createElement("div");
  head.className = "field-head";
  if (row.onNameChange) {
    head.append(input(row.name, t("field.name"), row.onNameChange));
  } else {
    const label = document.createElement("label");
    label.textContent = row.name;
    head.append(label);
  }
  if (row.ref) head.append(badge(`§${row.ref}`));
  // Marks a parameter the response will be compared against.
  if (row.checked) head.append(badge(row.checked, "blue"));
  field.append(head);

  if (row.onValueChange) {
    const line = document.createElement("div");
    line.className = "value-row";
    const value = input(row.value, t("field.value"), row.onValueChange);
    value.classList.add("protocol");
    value.setAttribute("aria-label", row.name || t("field.value"));
    line.append(value);
    if (row.onRemove) {
      const remove = document.createElement("button");
      remove.type = "button";
      remove.textContent = t("field.remove");
      remove.addEventListener("click", row.onRemove);
      line.append(remove);
    }
    field.append(line);
  } else {
    const value = document.createElement("code");
    value.className = "value";
    value.textContent = row.value === undefined || row.value === "" ? t("note.none") : row.value;
    field.append(value);
  }

  if (row.why) {
    const why = document.createElement("small");
    why.textContent = row.why;
    field.append(why);
  }
  return field;
}

function badge(text, kind) {
  const element = document.createElement("span");
  element.className = kind ? `badge ${kind}` : "badge";
  element.textContent = text;
  return element;
}

function input(value, placeholder, onChange) {
  const field = document.createElement("input");
  field.type = "text";
  field.value = value ?? "";
  field.placeholder = placeholder;
  field.spellcheck = false;
  field.autocapitalize = "off";
  field.autocomplete = "off";
  field.addEventListener("input", () => onChange(field.value));
  return field;
}
