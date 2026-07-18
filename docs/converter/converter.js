/* The converter deliberately has no dependencies and does not walk arbitrary input. */
const MAX_BYTES = 1024 * 1024;
const MAX_OUTBOUNDS = 32;
const MAX_DIAGNOSTICS = 64;

export function convertXrayConfig(text) {
  const diagnostics = [];
  let fatalSeen = false;
  let diagnosticOverflow = false;
  let sourceOutbounds = 0;
  let selectedCandidates = 0;
  let skipped = 0;
  const add = (severity, code, path, message) => { if (severity === "fatal") fatalSeen = true; if (diagnostics.length < MAX_DIAGNOSTICS - 2) diagnostics.push({ severity, code, path, message }); else diagnosticOverflow = true; };
  if (typeof text !== "string") {
    add("fatal", "invalid_input", "$", "Input must be JSON text.");
    return result(null, diagnostics, true, false, sourceOutbounds, selectedCandidates, skipped);
  }
  let bytes;
  try { bytes = new TextEncoder().encode(text).length; } catch (_) { bytes = text.length; }
  if (bytes > MAX_BYTES) {
    add("fatal", "input_too_large", "$", "Input exceeds the 1 MiB limit.");
    return result(null, diagnostics, true, false, sourceOutbounds, selectedCandidates, skipped);
  }
  let input;
  try { input = JSON.parse(text); } catch (_) {
    add("fatal", "malformed_json", "$", "Input is not valid JSON.");
    return result(null, diagnostics, true, false, sourceOutbounds, selectedCandidates, skipped);
  }
  if (!input || Array.isArray(input) || typeof input !== "object" || !Array.isArray(input.outbounds)) {
    add("fatal", "invalid_input_shape", "$", "Input must be an object with an outbounds array.");
    return result(null, diagnostics);
  }
  if (input.outbounds.length > MAX_OUTBOUNDS) {
    add("fatal", "too_many_outbounds", "outbounds", "Input contains more than 32 outbounds.");
    return result(null, diagnostics, true, false, input.outbounds.length, selectedCandidates, skipped);
  }
  sourceOutbounds = input.outbounds.length;

  const candidates = [];
  let ignored = 0;
  for (let i = 0; i < input.outbounds.length; i++) {
    const o = input.outbounds[i], p = `outbounds[${i}]`;
    if (!o || typeof o !== "object" || Array.isArray(o) || o.protocol !== "vless") { ignored++; continue; }
    const s = o.settings, st = o.streamSettings;
    if (s && Object.prototype.hasOwnProperty.call(s, "vnext")) {
      add("warning", "unsupported_input_shape", `${p}.settings.vnext`, "Nested VLESS settings/client-outbound shape is not supported.");
      ignored++;
      continue;
    }
    if (!s || typeof s !== "object" || Array.isArray(s)) {
      add("warning", "ignored_unsupported_vless", p, "VLESS outbound is not a flattened client outbound.");
      ignored++;
      continue;
    }
    if (!st || st.network !== "xhttp" || !["tls", "reality"].includes(st.security)) {
      add("warning", "ignored_unsupported_vless", `${p}.streamSettings`, "Only VLESS XHTTP over TLS or Reality client outbounds are supported.");
      ignored++;
      continue;
    }
    selectedCandidates++;
    if (Object.prototype.hasOwnProperty.call(st, "tlsSettings") && !isContainer(st.tlsSettings)) fatal(add, `${p}.streamSettings.tlsSettings`, "invalid_type", "TLS settings must be an object.");
    if (Object.prototype.hasOwnProperty.call(st, "xhttpSettings") && !isContainer(st.xhttpSettings)) fatal(add, `${p}.streamSettings.xhttpSettings`, "invalid_type", "XHTTP settings must be an object.");
    unknownKeys(o, ["protocol","tag","settings","streamSettings","listen","port","decryption","mux"], p, add, true);
    unknownKeys(s, ["address","port","id","flow","encryption","decryption","level"], `${p}.settings`, add, true);
    unknownKeys(st, ["network","security","tlsSettings","xhttpSettings","decryption","serverName","certificate","key","fallback","sniffing","allocation"], `${p}.streamSettings`, add, true);
    unknownKeys(st.tlsSettings, ["serverName","alpn","allowInsecure","fingerprint","settings","realitySettings","certificate","key"], `${p}.streamSettings.tlsSettings`, add, true);
    unknownKeys(st.xhttpSettings, ["path","mode","host","headers","xPaddingBytes","scMaxEachPostBytes","scMinPostsIntervalMs","sessionIDLength","uplinkChunkSize","sessionIDTable","sessionIDPlacement","sessionIDKey","seqPlacement","seqKey","uplinkDataPlacement","uplinkDataKey","uplinkHTTPMethod","noGRPCHeader","xPaddingMethod","xPaddingPlacement","xPaddingKey","xPaddingObfsMode","xPaddingHeader","xmux","decryption","scStreamUpServerSecs","scMaxBufferedPosts","noSSEHeader","serverMaxHeaderBytes","proxyProtocol","sniffing","allocation","fallback","serverName","certificate","key"], `${p}.streamSettings.xhttpSettings`, add, true);
    unknownKeys(st.xhttpSettings && st.xhttpSettings.xmux, ["maxConnections","maxConcurrency","cMaxReuseTimes","hMaxRequestTimes","hMaxReusableSecs","hKeepAlivePeriod"], `${p}.streamSettings.xhttpSettings.xmux`, add, true);
    if (Object.prototype.hasOwnProperty.call(o, "listen") || Object.prototype.hasOwnProperty.call(o, "port") || Object.prototype.hasOwnProperty.call(o, "decryption") || Object.prototype.hasOwnProperty.call(o, "mux") || Object.prototype.hasOwnProperty.call(st, "listen") || Object.prototype.hasOwnProperty.call(st, "port")) {
      add("fatal", "server_input", p, "Server-shaped VLESS input is not accepted.");
    }
    if (Object.prototype.hasOwnProperty.call(s, "decryption")) add("fatal", "server_input", `${p}.settings`, "Server decryption is not accepted.");
    candidates.push({ o, s, st, p });
  }
  skipped = ignored;
  if (ignored) add("warning", "ignored_non_vless", "outbounds", "Out-of-scope outbounds were skipped.");
  const tags = allocateTags(candidates);
  const converted = candidates.map((c, n) => convert(c, tags[n], add));
  if (!converted.length) add("fatal", "no_converted_outbounds", "outbounds", "No supported VLESS outbounds were found.");
  diagnostics.sort((a, b) => pathOrder(a.path) - pathOrder(b.path) || a.path.localeCompare(b.path) || a.code.localeCompare(b.code));
  return result(fatalSeen ? null : { outbounds: converted }, diagnostics, fatalSeen, diagnosticOverflow, sourceOutbounds, selectedCandidates, skipped);
}

function result(value, diagnostics, fatalSeen = diagnostics.some(d => d.severity === "fatal"), overflow = false, sourceOutbounds = 0, selectedCandidates = 0, skipped = 0) {
  if (overflow) {
    diagnostics.length = MAX_DIAGNOSTICS - 2;
    if (fatalSeen && !diagnostics.some(d => d.severity === "fatal")) diagnostics.unshift({ severity: "fatal", code: "fatal_summary", path: "$", message: "Conversion failed due to validation errors." });
    diagnostics.push({ severity: "warning", code: "diagnostics_truncated", path: "$", message: "Diagnostics were truncated." });
  }
  return { value, diagnostics, summary: { mode: "extraction_compatibility", source_outbounds: sourceOutbounds, selected_candidates: selectedCandidates, converted: value === null ? 0 : value.outbounds.length, skipped, state: fatalSeen ? "failure" : value !== null && skipped > 0 ? "partial" : "complete" } };
}
function unknownKeys(object, allowed, path, add, fatalUnknown) {
  if (!object || typeof object !== "object" || Array.isArray(object)) return;
  for (const key of Object.keys(object)) if (!allowed.includes(key)) add(fatalUnknown ? "fatal" : "warning", "unknown_field", `${path}.*`, "Unknown field is not supported.");
  if (path.endsWith(".settings") && Object.prototype.hasOwnProperty.call(object, "level")) add("warning", "omitted_metadata", `${path}.level`, "The level metadata field was omitted.");
}
function isContainer(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function pathOrder(path) { const m = /outbounds\[(\d+)\]/.exec(path); return m ? Number(m[1]) : -1; }
function allocateTags(cs) {
  const used = new Set(), out = [];
  for (const c of cs) {
    const t = c.o.tag;
    if (typeof t === "string" && t.trim() && !used.has(t)) { used.add(t); out.push(t); }
    else out.push(null);
  }
  let n = 1;
  for (let i = 0; i < out.length; i++) if (!out[i]) { while (used.has(`vless-${n}`)) n++; out[i] = `vless-${n++}`; used.add(out[i]); }
  return out;
}
function fatal(add, p, code, message) { add("fatal", code, p, message); }
function nonempty(v) { return v !== undefined && v !== null && v !== ""; }
function numericValue(v, p, name, add, positive = false) {
  if (!nonempty(v)) return undefined;
  const n = typeof v === "number" ? v : (typeof v === "string" && /^\d+$/.test(v) ? Number(v) : NaN);
  if (!Number.isSafeInteger(n) || (positive ? n <= 0 : n < 0)) { fatal(add, p, "invalid_range", `${name} must be a valid ${positive ? "positive " : ""}number.`); return undefined; }
  return n;
}
function range(v, p, name, add, positive) {
  if (!nonempty(v)) return undefined;
  if (typeof v === "number" || /^\d+$/.test(String(v))) return numericValue(v, p, name, add, positive);
  const m = /^(\d+)-(\d+)$/.exec(String(v));
  if (!m || !Number.isSafeInteger(Number(m[1])) || !Number.isSafeInteger(Number(m[2])) || Number(m[1]) > Number(m[2]) || (positive && Number(m[1]) <= 0)) { fatal(add, p, "invalid_range", `${name} must be a valid range.`); return undefined; }
  return `${Number(m[1])}-${Number(m[2])}`;
}
function xmuxLimit(v, p, name, add) {
  if (!nonempty(v)) return undefined;
  if (v === 0 || v === "0") return 0;
  return range(v, p, name, add, true);
}
function positiveMapped(v) {
  if (typeof v === "number") return v > 0;
  return typeof v === "string" && Number(v.split("-", 1)[0]) > 0;
}
function keepAlive(v, p, name, add) {
  if (!nonempty(v)) return undefined;
  return numericValue(v, p, name, add, false);
}
function enumValue(v, allowed, p, name, add) {
  if (!nonempty(v)) return undefined;
  if (!allowed.includes(v)) { fatal(add, p, "invalid_enum", `${name} has an unsupported value.`); return undefined; }
  return v;
}
function mapTls(tls, path, add, realitySecurity = false) {
  const output = { enabled: true };
  if (nonempty(tls.serverName)) { if (typeof tls.serverName !== "string") fatal(add, `${path}.streamSettings.tlsSettings.serverName`, "invalid_type", "TLS server name must be a string."); else output.server_name = tls.serverName; }
  if (tls.alpn !== undefined) { if (!Array.isArray(tls.alpn) || !tls.alpn.every(value => typeof value === "string")) fatal(add, `${path}.streamSettings.tlsSettings.alpn`, "invalid_type", "TLS ALPN must be an array of strings."); else output.alpn = tls.alpn; }
  const rootFingerprintPath = `${path}.streamSettings.tlsSettings.fingerprint`;
  const rootFingerprint = Object.prototype.hasOwnProperty.call(tls, "fingerprint") && tls.fingerprint !== "" ? mapFingerprint(tls.fingerprint, rootFingerprintPath, add) : undefined;
  let nestedFingerprint;
  if (Object.prototype.hasOwnProperty.call(tls, "settings")) {
    const settingsPath = `${path}.streamSettings.tlsSettings.settings`;
    if (!isContainer(tls.settings)) fatal(add, settingsPath, "invalid_type", "TLS settings must be an object.");
    else {
      unknownKeys(tls.settings, ["fingerprint"], settingsPath, add, true);
      if (Object.prototype.hasOwnProperty.call(tls.settings, "fingerprint")) nestedFingerprint = mapFingerprint(tls.settings.fingerprint, `${settingsPath}.fingerprint`, add);
    }
  }
  if (nestedFingerprint !== undefined && rootFingerprint !== undefined && nestedFingerprint !== rootFingerprint) {
    fatal(add, `${path}.streamSettings.tlsSettings`, "conflicting_fingerprint", "Root and nested TLS fingerprints disagree.");
  }
  const fingerprint = nestedFingerprint ?? rootFingerprint ?? "chrome";
  if (fingerprint !== undefined) output.utls = { enabled: true, fingerprint };
  if (Object.prototype.hasOwnProperty.call(tls, "allowInsecure")) {
    if (typeof tls.allowInsecure !== "boolean") fatal(add, `${path}.streamSettings.tlsSettings.allowInsecure`, "invalid_type", "TLS allowInsecure must be boolean.");
    else if (tls.allowInsecure) fatal(add, `${path}.streamSettings.tlsSettings.allowInsecure`, "invalid_tls", "Pinned Xray rejects allowInsecure=true.");
  }
  if (realitySecurity) mapReality(output, tls, path, add);
  else if (Object.prototype.hasOwnProperty.call(tls, "realitySettings")) fatal(add, `${path}.streamSettings.tlsSettings.realitySettings`, "unsupported_security", "Reality settings require security=reality.");
  return output;
}
function base64UrlBytes(value, expected) {
  return typeof value === "string" && /^[A-Za-z0-9_-]+$/.test(value) && value.length % 4 !== 1 && Math.floor(value.length * 6 / 8) === expected;
}
function mapReality(output, tls, path, add) {
  const realityPath = `${path}.streamSettings.tlsSettings.realitySettings`;
  if (!Object.prototype.hasOwnProperty.call(tls, "realitySettings")) { fatal(add, realityPath, "invalid_required_field", "Reality settings are required."); return; }
  const settings = tls.realitySettings;
  if (!isContainer(settings)) { fatal(add, realityPath, "invalid_type", "Reality settings must be an object."); return; }
  unknownKeys(settings, ["publicKey", "shortId"], realityPath, add, true);
  if (!Object.prototype.hasOwnProperty.call(settings, "publicKey")) fatal(add, `${realityPath}.publicKey`, "invalid_required_field", "Reality public key is required.");
  else if (!base64UrlBytes(settings.publicKey, 32)) fatal(add, `${realityPath}.publicKey`, "invalid_reality", "Reality public key must be 32-byte unpadded base64url.");
  else {
    const reality = output.reality = { enabled: true, public_key: settings.publicKey };
    if (Object.prototype.hasOwnProperty.call(settings, "shortId")) {
      if (typeof settings.shortId !== "string" || !/^(?:[0-9a-fA-F]{2}){0,8}$/.test(settings.shortId)) fatal(add, `${realityPath}.shortId`, "invalid_reality", "Reality short ID must be even-length hexadecimal up to 8 bytes.");
      else if (settings.shortId !== "") reality.short_id = settings.shortId;
    }
  }
}
function mapFingerprint(fingerprint, path, add) {
  if (typeof fingerprint !== "string") { fatal(add, path, "invalid_type", "TLS fingerprint must be a string."); return undefined; }
  const canonical = { chrome: "chrome", firefox: "firefox", edge: "edge", safari: "safari", 360: "360", qq: "qq", ios: "ios", android: "android" };
  const aliases = { hellochrome_auto: "chrome", hellofirefox_auto: "firefox", helloedge_auto: "edge", hellosafari_auto: "safari", hello360_auto: "360", helloqq_auto: "qq", helloios_auto: "ios", helloandroid_11_okhttp: "android" };
  const normalized = fingerprint.toLowerCase();
  if (canonical[normalized]) return canonical[normalized];
  if (aliases[normalized]) { add("warning", "normalized_fingerprint", path, "A pinned source auto alias was normalized to a canonical target fingerprint."); return aliases[normalized]; }
  fatal(add, path, "unsupported_fingerprint", "TLS fingerprint is not supported by the pinned baseline.");
  return undefined;
}
function mapHeaders(transport, xhttp, path, add) {
  if (xhttp.headers === undefined) return;
  if (!isContainer(xhttp.headers)) { fatal(add, `${path}.streamSettings.xhttpSettings.headers`, "invalid_type", "XHTTP headers must be a string map."); return; }
  transport.headers = {};
  for (const key of Object.keys(xhttp.headers)) {
    const value = xhttp.headers[key];
    if (/[\r\n]/.test(key)) fatal(add, `${path}.streamSettings.xhttpSettings.headers[*]`, "invalid_header", "XHTTP header names must not contain line breaks.");
    else if (key.toLowerCase() === "host") fatal(add, `${path}.streamSettings.xhttpSettings.headers[*]`, "host_header_conflict", "Host must be specified with the host field.");
    else if (typeof value !== "string") fatal(add, `${path}.streamSettings.xhttpSettings.headers[*]`, "invalid_type", "XHTTP header values must be strings.");
    else if (/[\r\n]/.test(value)) fatal(add, `${path}.streamSettings.xhttpSettings.headers[*]`, "invalid_header", "XHTTP header values must not contain line breaks.");
    else Object.defineProperty(transport.headers, key, { value, enumerable: true, configurable: true, writable: true });
  }
}
function mapRanges(transport, xhttp, path, add) {
  const fields = [["xPaddingBytes","x_padding_bytes",true],["scMaxEachPostBytes","sc_max_each_post_bytes",true],["scMinPostsIntervalMs","sc_min_posts_interval_ms",false],["sessionIDLength","session_id_length",true],["uplinkChunkSize","uplink_chunk_size",true]];
  for (const [source, target, positive] of fields) { const value = range(xhttp[source], `${path}.streamSettings.xhttpSettings.${source}`, source, add, positive); if (value !== undefined) transport[target] = value; }
  if (!nonempty(xhttp.xPaddingBytes)) fatal(add, `${path}.streamSettings.xhttpSettings.xPaddingBytes`, "invalid_required_field", "XHTTP padding bytes are required.");
}
function mapXmux(transport, xhttp, path, add) {
  if (xhttp.xmux !== undefined && (!xhttp.xmux || typeof xhttp.xmux !== "object" || Array.isArray(xhttp.xmux))) { fatal(add, `${path}.streamSettings.xhttpSettings.xmux`, "invalid_type", "XMUX must be an object."); return; }
  if (!xhttp.xmux) return;
  const output = {};
  for (const [source, target, kind] of [["maxConnections","max_connections","limit"],["maxConcurrency","max_concurrency","limit"],["cMaxReuseTimes","c_max_reuse_times","range"],["hMaxRequestTimes","h_max_request_times","positiveRange"],["hMaxReusableSecs","h_max_reusable_secs","positiveRange"],["hKeepAlivePeriod","h_keep_alive_period","integer"]]) {
    const value = kind === "limit" ? xmuxLimit(xhttp.xmux[source], `${path}.streamSettings.xhttpSettings.xmux.${source}`, source, add) : kind === "integer" ? keepAlive(xhttp.xmux[source], `${path}.streamSettings.xhttpSettings.xmux.${source}`, source, add) : range(xhttp.xmux[source], `${path}.streamSettings.xhttpSettings.xmux.${source}`, source, add, kind === "positiveRange");
    if (value !== undefined) output[target] = value;
  }
  if (positiveMapped(output.max_connections) && positiveMapped(output.max_concurrency)) fatal(add, `${path}.streamSettings.xhttpSettings.xmux`, "xmux_conflict", "max_connections and max_concurrency are mutually exclusive.");
  if (Object.keys(output).length) transport.xmux = output;
}
function validEncryptionKey(segment) {
  if (!/^[A-Za-z0-9_-]+$/.test(segment) || segment.length % 4 === 1) return false;
  return Math.floor(segment.length * 6 / 8) === 32 || Math.floor(segment.length * 6 / 8) === 1184;
}
function validEncryption(value) {
  if (typeof value !== "string") return false;
  const parts = value.trim().split(".");
  if (parts.length < 4 || parts[0] !== "mlkem768x25519plus" || !["native", "xorpub", "random"].includes(parts[1]) || !["0rtt", "1rtt"].includes(parts[2])) return false;
  let keySeen = false;
  for (const segment of parts.slice(3)) {
    if (!segment.trim()) return false;
    if (validEncryptionKey(segment.trim())) keySeen = true;
    else if (keySeen) return false;
  }
  return keySeen;
}
function convert(c, tag, add) {
  const { o, s, st, p } = c, t = { type: "vless", tag, server: s.address, server_port: numericValue(s.port, `${p}.settings.port`, "Port", add, true), uuid: typeof s.id === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s.id) ? s.id : undefined };
  if (typeof s.address !== "string" || !s.address.trim() || /[\r\n]/.test(s.address) || t.server_port === undefined || t.server_port > 65535 || !t.uuid) fatal(add, p, "invalid_required_field", "Server, port, and UUID must be valid.");
  if (nonempty(s.flow)) {
    if (s.flow === "xtls-rprx-vision") t.flow = s.flow;
    else fatal(add, `${p}.settings.flow`, "unsupported_flow", "Only xtls-rprx-vision VLESS flow is supported.");
  }
  if (Object.prototype.hasOwnProperty.call(s, "encryption")) {
    if (typeof s.encryption !== "string") fatal(add, `${p}.settings.encryption`, "invalid_type", "Encryption must be a string.");
    else if (s.encryption !== "none" && nonempty(s.encryption)) {
      if (!validEncryption(s.encryption)) fatal(add, `${p}.settings.encryption`, "unsupported_encryption", "VLESS encryption does not match the pinned baseline format.");
      else t.encryption = s.encryption;
    }
  }
  const tls = isContainer(st.tlsSettings) ? st.tlsSettings : {}, x = isContainer(st.xhttpSettings) ? st.xhttpSettings : {};
  t.tls = mapTls(tls, p, add, st.security === "reality");
  const tr = t.transport = { type: "xhttp" };
  if (typeof x.path !== "string" || !x.path.startsWith("/")) fatal(add, `${p}.streamSettings.xhttpSettings.path`, "invalid_required_field", "XHTTP path must begin with '/'."); else tr.path = x.path;
  if (!nonempty(x.mode)) fatal(add, `${p}.streamSettings.xhttpSettings.mode`, "invalid_required_field", "XHTTP mode is required.");
  else tr.mode = enumValue(x.mode, ["auto", "packet-up", "stream-up", "stream-one"], `${p}.streamSettings.xhttpSettings.mode`, "XHTTP mode", add);
  if (nonempty(x.host)) { if (typeof x.host !== "string") fatal(add, `${p}.streamSettings.xhttpSettings.host`, "invalid_type", "XHTTP host must be a string."); else tr.host = x.host; }
  mapHeaders(tr, x, p, add);
  mapRanges(tr, x, p, add);
  for (const [a,b] of [["sessionIDTable","session_id_table"],["sessionIDPlacement","session_placement"],["sessionIDKey","session_key"],["seqPlacement","seq_placement"],["seqKey","seq_key"],["uplinkDataPlacement","uplink_data_placement"],["uplinkDataKey","uplink_data_key"],["uplinkHTTPMethod","uplink_http_method"],["noGRPCHeader","no_grpc_header"]]) {
    if (!nonempty(x[a])) continue; let v=x[a];
    if (["sessionIDTable","sessionIDKey","seqKey","uplinkDataKey"].includes(a) && typeof v !== "string") { fatal(add, `${p}.streamSettings.xhttpSettings.${a}`, "invalid_type", "XHTTP key fields must be strings."); continue; }
    if (a === "sessionIDPlacement" || a === "seqPlacement") v=enumValue(v,["path","cookie","header","query"],`${p}.streamSettings.xhttpSettings.${a}`,a,add);
    else if (a === "uplinkDataPlacement") v=enumValue(v,["auto","body","cookie","header"],`${p}.streamSettings.xhttpSettings.${a}`,a,add);
    else if (a === "uplinkHTTPMethod") v=enumValue(v,["GET","POST"],`${p}.streamSettings.xhttpSettings.${a}`,a,add);
    else if (a === "noGRPCHeader" && typeof v !== "boolean") { fatal(add, `${p}.streamSettings.xhttpSettings.${a}`, "invalid_type", "Field must be boolean."); v=undefined; }
    if(v!==undefined) tr[b]=v;
  }
  if ((x.uplinkHTTPMethod === "GET" || x.uplinkDataPlacement === "cookie" || x.uplinkDataPlacement === "header") && x.mode !== "packet-up") fatal(add, `${p}.streamSettings.xhttpSettings`, "invalid_combination", "This uplink setting requires packet-up mode.");
  for (const [a,b] of [["xPaddingMethod","x_padding_method"],["xPaddingPlacement","x_padding_placement"],["xPaddingKey","x_padding_key"]]) {
    if (!nonempty(x[a])) continue;
    let v=x[a];
    if ((a === "xPaddingKey" || a === "xPaddingPlacement") && typeof v !== "string") { fatal(add, `${p}.streamSettings.xhttpSettings.${a}`, "invalid_type", "Padding field must be a string."); continue; }
    if (a === "xPaddingMethod") v=enumValue(v,["repeat-x","tokenish"],`${p}.streamSettings.xhttpSettings.${a}`,a,add);
    if (a === "xPaddingPlacement") v=enumValue(v,["cookie","header","query","queryInHeader"],`${p}.streamSettings.xhttpSettings.${a}`,a,add);
    if(v!==undefined) tr[b]=v;
  }
  if (nonempty(x.xPaddingObfsMode)) {
    if (typeof x.xPaddingObfsMode !== "boolean") fatal(add, `${p}.streamSettings.xhttpSettings.xPaddingObfsMode`, "invalid_type", "Padding obfuscation mode must be boolean.");
    else tr.x_padding_obfs_mode = x.xPaddingObfsMode;
  }
  if (nonempty(x.xPaddingHeader)) { if (typeof x.xPaddingHeader !== "string") fatal(add, `${p}.streamSettings.xhttpSettings.xPaddingHeader`, "invalid_type", "Padding header must be a string."); else tr.x_padding_header = x.xPaddingHeader; }
  mapXmux(tr, x, p, add);
  for (const k of ["scStreamUpServerSecs","scMaxBufferedPosts","noSSEHeader","serverMaxHeaderBytes","proxyProtocol","sniffing","allocation","fallback","serverName","certificate","key","decryption"]) {
    const parent = Object.prototype.hasOwnProperty.call(x, k) ? `${p}.streamSettings.xhttpSettings` : Object.prototype.hasOwnProperty.call(st, k) ? `${p}.streamSettings` : Object.prototype.hasOwnProperty.call(o, k) ? p : null;
    if (parent) fatal(add, `${parent}.${k}`, "server_input", "Server-only or unrepresentable field is not accepted.");
  }
  for (const k of ["certificate", "key"]) if (Object.prototype.hasOwnProperty.call(tls, k)) fatal(add, `${p}.streamSettings.tlsSettings.${k}`, "server_input", "Server-only TLS field is not accepted.");
  return t;
}
