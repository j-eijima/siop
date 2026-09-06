// Renders a parameter list as a table: the value plus why the parameter is
// there. The point of this RP is to make each protocol field visible.
// Rows can be read-only (received response) or editable (outgoing request).

export function renderParams(table, rows) {
  table.innerHTML = "";
  for (const row of rows) {
    table.append(buildRow(row));
  }
}

function buildRow(row) {
  const tr = document.createElement("tr");
  const th = document.createElement("th");
  const td = document.createElement("td");

  if (row.onNameChange) {
    th.append(input(row.name, "パラメータ名", row.onNameChange));
  } else {
    th.textContent = row.name;
  }

  if (row.onValueChange) {
    const line = document.createElement("div");
    line.className = "value-row";
    line.append(input(row.value, "値", row.onValueChange));
    if (row.onRemove) {
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "remove";
      remove.textContent = "削除";
      remove.addEventListener("click", row.onRemove);
      line.append(remove);
    }
    td.append(line);
  } else {
    const value = document.createElement("div");
    value.className = "value";
    value.textContent = row.value === undefined || row.value === "" ? "(なし)" : row.value;
    td.append(value);
  }

  if (row.why || row.ref) {
    const why = document.createElement("div");
    why.className = "why";
    if (row.ref) {
      const ref = document.createElement("span");
      ref.className = "ref";
      ref.textContent = `Section ${row.ref}`;
      why.append(ref);
      if (row.why) why.append(document.createTextNode(" — "));
    }
    if (row.why) why.append(document.createTextNode(row.why));
    td.append(why);
  }

  tr.append(th, td);
  return tr;
}

function input(value, placeholder, onChange) {
  const field = document.createElement("input");
  field.type = "text";
  field.value = value ?? "";
  field.placeholder = placeholder;
  field.spellcheck = false;
  field.autocapitalize = "off";
  field.addEventListener("input", () => onChange(field.value));
  return field;
}
