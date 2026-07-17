import { convertXrayConfig } from "./converter.js";

const input = document.getElementById("xray-input");
const output = document.getElementById("output-json");
const convertButton = document.getElementById("convert-button");
const clearButton = document.getElementById("clear-button");
const copyButton = document.getElementById("copy-button");
const downloadButton = document.getElementById("download-button");
const emptyState = document.getElementById("empty-state");
const diagnostics = document.getElementById("diagnostics");
const errorState = document.getElementById("error-state");
const successState = document.getElementById("success-state");
const diagnosticCount = document.getElementById("diagnostic-count");
const outputMeta = document.getElementById("output-meta");

let downloadUrl = null;

function setHidden(element, hidden) {
  element.hidden = hidden;
}

function clearDownloadUrl() {
  if (downloadUrl) URL.revokeObjectURL(downloadUrl);
  downloadUrl = null;
}

function renderInitialDiagnostics() {
  diagnostics.replaceChildren();
  diagnostics.className = "diagnostics diagnostics-empty";
  const icon = document.createElement("span");
  icon.className = "report-icon";
  icon.setAttribute("aria-hidden", "true");
  icon.textContent = "✓";
  const message = document.createElement("p");
  message.textContent = "Сообщения появятся после запуска конвертации.";
  diagnostics.append(icon, message);
  diagnosticCount.textContent = "0 сообщений";
}

function renderDiagnostics(items) {
  diagnostics.replaceChildren();
  if (!items.length) {
    renderInitialDiagnostics();
    return;
  }
  diagnostics.className = "diagnostics diagnostics-list";
  for (const item of items) {
    const row = document.createElement("p");
    row.className = `diagnostic-row ${item.severity === "fatal" ? "diagnostic-fatal" : "diagnostic-warning"}`;
    row.textContent = `${item.severity} · ${item.code} · ${item.path} · ${item.message}`;
    diagnostics.append(row);
  }
  diagnosticCount.textContent = `${items.length} ${items.length === 1 ? "сообщение" : "сообщений"}`;
}

function setOutput(value) {
  const hasOutput = typeof value === "string" && value.length > 0;
  output.value = hasOutput ? value : "";
  setHidden(emptyState, hasOutput);
  copyButton.disabled = !hasOutput;
  downloadButton.disabled = !hasOutput;
}

function showStatus(kind) {
  setHidden(errorState, kind !== "error");
  setHidden(successState, kind !== "success");
}

function convert() {
  clearDownloadUrl();
  let result;
  try {
    result = convertXrayConfig(input.value);
  } catch (_) {
    result = { value: null, diagnostics: [{ severity: "fatal", code: "conversion_failed", path: "$", message: "Conversion failed." }] };
  }
  const serialized = result.value === null ? "" : JSON.stringify(result.value, null, 2);
  setOutput(serialized);
  renderDiagnostics(result.diagnostics);
  showStatus(result.value === null ? "error" : "success");
  outputMeta.textContent = result.value === null ? "Результат не создан" : `${result.value.outbounds.length} outbound${result.value.outbounds.length === 1 ? "" : "s"}`;
}

async function copyOutput() {
  if (!output.value) return;
  try {
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") await navigator.clipboard.writeText(output.value);
    else {
      try {
        output.focus();
        output.select();
        if (!document.execCommand("copy")) throw new Error("copy failed");
      } finally {
        copyButton.focus();
      }
    }
    outputMeta.textContent = "Скопировано";
  } catch (_) {
    outputMeta.textContent = "Не удалось скопировать";
  }
}

function downloadOutput() {
  if (!output.value) return;
  try {
    clearDownloadUrl();
    const blob = new Blob([output.value], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    downloadUrl = url;
    const link = document.createElement("a");
    link.href = url;
    link.download = "sing-box-extended-outbounds.json";
    document.body.append(link);
    try {
      link.click();
      outputMeta.textContent = "Скачивание начато";
    } finally {
      link.remove();
    }
    setTimeout(() => {
      if (downloadUrl === url) clearDownloadUrl();
      else URL.revokeObjectURL(url);
    }, 1000);
  } catch (_) {
    outputMeta.textContent = "Не удалось начать скачивание";
    clearDownloadUrl();
  }
}

function clear() {
  input.value = "";
  setOutput("");
  outputMeta.textContent = "Ожидает ввода";
  renderInitialDiagnostics();
  showStatus("empty");
  clearDownloadUrl();
  input.focus();
}

convertButton.addEventListener("click", convert);
clearButton.addEventListener("click", clear);
copyButton.addEventListener("click", copyOutput);
downloadButton.addEventListener("click", downloadOutput);
input.addEventListener("keydown", event => {
  if ((event.ctrlKey || event.metaKey) && event.key === "Enter") convert();
});

setOutput("");
