import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

// Loading by data URL keeps this repository's standalone .js ES module usable
// without adding a package-level module-type setting.
const source = await readFile(new URL("../../docs/converter/converter.js", import.meta.url), "utf8");
const { convertXrayConfig } = await import(`data:text/javascript,${encodeURIComponent(source)}`);
const id = "00000000-0000-4000-8000-000000000001";
const encryptionKey = "A".repeat(43);
const realityPublicKey = "A".repeat(43);
const base = (extra = {}) => ({
  protocol: "vless",
  tag: "client",
  settings: {
    address: "synthetic.invalid",
    port: 443,
    id,
    ...extra.settings
  },
  streamSettings: {
    network: "xhttp",
    security: "tls",
    tlsSettings: {
      serverName: "synthetic.invalid",
      fingerprint: "chrome"
    },
    xhttpSettings: {
      path: "/unit",
      mode: "auto",
      xPaddingBytes: 1,
      ...extra.xhttp
    },
    ...extra.streamSettings
  }
});
const run = (outbounds) => convertXrayConfig(JSON.stringify({ outbounds }));

test("maps Vision and validated VLESS encryption", () => {
  const encryption = `mlkem768x25519plus.native.1rtt.padding.${encryptionKey}`;
  const r = run([base({ settings: { flow: "xtls-rprx-vision", encryption }, xhttp: { host: "synthetic.invalid", headers: { "X-Test": "ok" } } })]);
  assert.equal(r.diagnostics.filter(d => d.severity === "fatal").length, 0);
  assert.equal(r.value.outbounds[0].flow, "xtls-rprx-vision");
  assert.equal(r.value.outbounds[0].encryption, encryption);
});

test("rejects unknown flow and invalid VLESS encryption", () => {
  const unknownFlow = run([base({ settings: { flow: "vision-but-not-exact" } })]);
  assert.equal(unknownFlow.value, null);
  assert.ok(unknownFlow.diagnostics.some(d => d.code === "unsupported_flow"));
  for (const encryption of ["mlkem768x25519plus.native.1rtt", "mlkem768x25519plus.bad.1rtt.x", `mlkem768x25519plus.native.1rtt.${encryptionKey}!`, `other.native.1rtt.${encryptionKey}`]) {
    const r = run([base({ settings: { encryption } })]);
    assert.equal(r.value, null);
    assert.ok(r.diagnostics.some(d => d.code === "unsupported_encryption"));
  }
});

test("normalizes ranges and XMUX, and enforces exclusivity", () => {
  const good = run([base({ xhttp: { xPaddingBytes: "1-8", sessionIDLength: "16", xmux: { maxConnections: "6", maxConcurrency: "", cMaxReuseTimes: 0, hMaxRequestTimes: "600-900", hMaxReusableSecs: "1800-3000", hKeepAlivePeriod: 0 } } })]);
  assert.equal(good.value.outbounds[0].transport.x_padding_bytes, "1-8");
  assert.equal(good.value.outbounds[0].transport.session_id_length, 16);
  assert.equal(good.value.outbounds[0].transport.xmux.max_connections, 6);
  assert.equal(good.value.outbounds[0].transport.xmux.c_max_reuse_times, 0);
  assert.equal(good.value.outbounds[0].transport.xmux.h_max_request_times, "600-900");
  assert.equal(good.value.outbounds[0].transport.xmux.h_max_reusable_secs, "1800-3000");
  assert.equal(good.value.outbounds[0].transport.xmux.h_keep_alive_period, 0);
  const bad = run([base({ xhttp: { xPaddingBytes: "0-4", xmux: { maxConnections: "6", maxConcurrency: 2 } } })]);
  assert.equal(bad.value, null);
  assert.ok(bad.diagnostics.some(d => d.code === "xmux_conflict"));
});

test("preserves numeric zero XMUX limits without a conflict", () => {
  const r = run([base({ xhttp: { xmux: { maxConnections: 0, maxConcurrency: "0" } } })]);
  assert.equal(r.diagnostics.filter(d => d.severity === "fatal").length, 0);
  assert.deepEqual(r.value.outbounds[0].transport.xmux, { max_connections: 0, max_concurrency: 0 });
});

test("maps advanced client padding fields and does not map allowInsecure", () => {
  const rejected = run([base({ streamSettings: { tlsSettings: { allowInsecure: true } } })]);
  assert.equal(rejected.value, null);
  assert.ok(rejected.diagnostics.some(d => d.code === "invalid_tls"));
  const r = run([base({ xhttp: { xPaddingObfsMode: true, xPaddingKey: "synthetic-key", xPaddingHeader: "X-Pad", xPaddingPlacement: "header", xPaddingMethod: "tokenish" } })]);
  const t = r.value.outbounds[0];
  assert.equal(t.tls.enabled, true);
  assert.equal(t.tls.insecure, undefined);
  assert.deepEqual(t.transport.x_padding_obfs_mode, true);
  assert.equal(t.transport.x_padding_key, "synthetic-key");
  assert.equal(t.transport.x_padding_header, "X-Pad");
  assert.equal(t.transport.x_padding_placement, "header");
  assert.equal(t.transport.x_padding_method, "tokenish");
});

test("rejects invalid ranges and Host header conflict", () => {
  const r = run([base({ xhttp: { xPaddingBytes: "9-2", headers: { Host: "bad" } } })]);
  assert.equal(r.value, null);
  assert.ok(r.diagnostics.some(d => d.code === "invalid_range"));
  assert.ok(r.diagnostics.some(d => d.code === "host_header_conflict"));
});

test("enforces required padding, bounded ports, safe ranges, and XMUX shape", () => {
  assert.equal(run([base({ xhttp: { xPaddingBytes: 0 } })]).value, null);
  assert.equal(run([base({ xhttp: { xPaddingBytes: "" } })]).value, null);
  assert.equal(run([base({ settings: { port: 65536 } })]).value, null);
  assert.equal(run([base({ xhttp: { scMaxEachPostBytes: "999999999999999999999-999999999999999999999" } })]).value, null);
  assert.equal(run([base({ xhttp: { xmux: { hKeepAlivePeriod: "1-2" } } })]).value, null);
  assert.equal(run([base({ xhttp: { xmux: null } })]).value, null);
  assert.equal(run([base({ xhttp: { xmux: [] } })]).value, null);
});

test("requires positive post padding ranges in auto and packet-up modes", () => {
  assert.equal(run([base({ xhttp: { scMaxEachPostBytes: 0 } })]).value, null);
  assert.equal(run([base({ xhttp: { scMaxEachPostBytes: "0-4" } })]).value, null);
  assert.equal(run([base({ xhttp: { mode: "packet-up", scMaxEachPostBytes: 0 } })]).value, null);
  assert.equal(run([base({ xhttp: { mode: "packet-up", scMaxEachPostBytes: "0-4" } })]).value, null);
});

test("validates containers, preserves __proto__, and rejects allowInsecure", () => {
  for (const field of ["tlsSettings", "xhttpSettings"]) {
    const streamSettings = { network: "xhttp", security: "tls", [field]: null };
    assert.equal(run([base({ streamSettings })]).value, null);
  }
  assert.equal(run([base({ xhttp: { xmux: "bad" } })]).value, null);
  const rejected = run([base({ streamSettings: { tlsSettings: { allowInsecure: true } } })]);
  assert.equal(rejected.value, null);
  assert.ok(rejected.diagnostics.some(d => d.code === "invalid_tls"));
  const headers = JSON.parse('{"__proto__":"synthetic"}');
  const r = run([base({ xhttp: { headers } })]);
  assert.equal(r.value.outbounds[0].transport.headers["__proto__"], "synthetic");
  assert.equal(Object.prototype.hasOwnProperty.call(r.value.outbounds[0].transport.headers, "__proto__"), true);
  assert.equal(r.diagnostics.filter(d => d.severity === "fatal").length, 0);
});

test("maps nested TLS fingerprint settings and rejects unsupported or conflicting forms", () => {
  const nested = run([base({ streamSettings: { tlsSettings: { settings: { fingerprint: "hellofirefox_auto" } } } })]);
  assert.equal(nested.value.outbounds[0].tls.utls.fingerprint, "firefox");
  assert.ok(nested.diagnostics.some(d => d.code === "normalized_fingerprint"));
  const unknown = run([base({ streamSettings: { tlsSettings: { settings: { fingerprint: "chrome", other: true } } } })]);
  assert.equal(unknown.value, null);
  assert.ok(unknown.diagnostics.some(d => d.code === "unknown_field" && d.path.endsWith(".settings.*")));
  const conflict = run([base({ streamSettings: { tlsSettings: { fingerprint: "chrome", settings: { fingerprint: "firefox" } } } })]);
  assert.equal(conflict.value, null);
  assert.ok(conflict.diagnostics.some(d => d.code === "conflicting_fingerprint"));
});

test("maps Reality with Vision and default uTLS", () => {
  const r = run([base({ settings: { flow: "xtls-rprx-vision" }, streamSettings: {
    security: "reality",
    tlsSettings: { serverName: "synthetic.invalid", fingerprint: "chrome", realitySettings: { publicKey: realityPublicKey, shortId: "0123abcd" } }
  } })]);
  assert.equal(r.diagnostics.filter(d => d.severity === "fatal").length, 0);
  assert.equal(r.value.outbounds[0].flow, "xtls-rprx-vision");
  assert.deepEqual(r.value.outbounds[0].tls, { enabled: true, server_name: "synthetic.invalid", utls: { enabled: true, fingerprint: "chrome" }, reality: { enabled: true, public_key: realityPublicKey, short_id: "0123abcd" } });
});

test("rejects malformed Reality keys, short IDs, and missing settings", () => {
  const reality = (realitySettings) => run([base({ streamSettings: { security: "reality", tlsSettings: { realitySettings } } })]);
  for (const publicKey of ["A".repeat(42), `${realityPublicKey} `]) {
    const r = reality({ publicKey });
    assert.equal(r.value, null);
    assert.ok(r.diagnostics.some(d => d.code === "invalid_reality"));
  }
  for (const shortId of ["123", "0".repeat(18)]) {
    const r = reality({ publicKey: realityPublicKey, shortId });
    assert.equal(r.value, null);
    assert.ok(r.diagnostics.some(d => d.code === "invalid_reality"));
  }
  const missing = run([base({ streamSettings: { security: "reality", tlsSettings: {} } })]);
  assert.equal(missing.value, null);
  assert.ok(missing.diagnostics.some(d => d.code === "invalid_required_field"));
  const nonContainer = reality(null);
  assert.equal(nonContainer.value, null);
  assert.ok(nonContainer.diagnostics.some(d => d.code === "invalid_type"));
  const missingPublicKey = reality({});
  assert.equal(missingPublicKey.value, null);
  assert.ok(missingPublicKey.diagnostics.some(d => d.code === "invalid_required_field"));
});

test("rejects unknown and server-only Reality settings without echoing values", () => {
  for (const key of ["privateKey", "shortIds", "target", "dest", "xver", "show", "spiderX", "mldsa65Verify"]) {
    const marker = `secret-${key}`;
    const r = run([base({ streamSettings: { security: "reality", tlsSettings: { realitySettings: { publicKey: realityPublicKey, [key]: marker } } } })]);
    assert.equal(r.value, null);
    assert.ok(r.diagnostics.some(d => d.code === "unknown_field"));
    assert.equal(JSON.stringify(r.diagnostics).includes(marker), false);
  }
});

test("rejects flattened settings decryption and mapped type errors", () => {
  const decryption = run([base({ settings: { decryption: "none" } })]);
  assert.equal(decryption.value, null);
  assert.ok(decryption.diagnostics.some(d => d.code === "server_input" && d.path.endsWith(".settings")));
  assert.equal(run([base({ settings: { encryption: 3 } })]).value, null);
  assert.equal(run([base({ streamSettings: { tlsSettings: { alpn: ["h2", 3] } } })]).value, null);
});

test("diagnostics are private, ordered, and capped", () => {
  const headers = { "X-Leak\nName": "secret\r\nvalue" };
  const r = run(Array.from({ length: 32 }, (_, i) => base({ tag: `vless-${i + 1}`, xhttp: { headers, xPaddingBytes: 0, unknownClientField: true } })));
  assert.equal(r.value, null);
  assert.ok(r.diagnostics.length <= 64);
  assert.equal(r.diagnostics.filter(d => d.code === "diagnostics_truncated").length, 1);
  assert.ok(r.diagnostics.some(d => d.code === "fatal_summary" || d.severity === "fatal"));
  const serialized = JSON.stringify(r.diagnostics);
  assert.equal(serialized.includes("X-Leak"), false);
  assert.equal(serialized.includes("secret"), false);
  for (let i = 1; i < r.diagnostics.length; i++) {
    const a = r.diagnostics[i - 1], b = r.diagnostics[i];
    if (b.code === "diagnostics_truncated") continue;
    const ai = Number(a.path.match(/outbounds\[(\d+)\]/)?.[1] ?? -1);
    const bi = Number(b.path.match(/outbounds\[(\d+)\]/)?.[1] ?? -1);
    assert.ok(ai < bi || (ai === bi && a.path.localeCompare(b.path) <= 0));
  }
});

test("rejects invalid servers and header injection", () => {
  assert.equal(run([base({ settings: { address: "" } })]).value, null);
  assert.equal(run([base({ xhttp: { headers: { "X-Bad\nName": "ok" } } })]).value, null);
  assert.equal(run([base({ xhttp: { headers: { "X-Bad": "ok\r\nInjected: yes" } } })]).value, null);
});

test("rejects server-only fields and server shape", () => {
  const rejected = run([base({ xhttp: { scMaxBufferedPosts: 2 } })]);
  assert.equal(rejected.value, null);
  assert.ok(rejected.diagnostics.some(d => d.code === "server_input" && d.path.endsWith(".streamSettings.xhttpSettings.scMaxBufferedPosts")));
  const streamRejected = run([base({ streamSettings: {
    network: "xhttp",
    security: "tls",
    tlsSettings: { serverName: "synthetic.invalid" },
    xhttpSettings: { path: "/unit", mode: "auto", xPaddingBytes: 1 },
    serverName: "synthetic.invalid"
  } })]);
  assert.equal(streamRejected.value, null);
  assert.ok(streamRejected.diagnostics.some(d => d.code === "server_input" && d.path.endsWith(".streamSettings.serverName")));
  const serverShapeRejected = run([{ ...base(), decryption: "none" }]);
  assert.equal(serverShapeRejected.value, null);
  assert.ok(serverShapeRejected.diagnostics.some(d => d.code === "server_input"));
});

test("allocates deterministic tags and keeps all-or-nothing semantics", () => {
  const first = base();
  const second = { ...base(), tag: "client" };
  const third = { ...base(), tag: "kept" };
  const r = run([first, { protocol: "freedom" }, second, third]);
  assert.deepEqual(r.value.outbounds.map(o => o.tag), ["client", "vless-1", "kept"]);
  // Make the second candidate invalid: one eligible failure invalidates the whole bundle.
  const invalid = run([first, base({ settings: { port: 0 } })]);
  assert.equal(invalid.value, null);
  assert.ok(invalid.diagnostics.some(d => d.code === "invalid_required_field"));
});

test("handles malformed input, limits, and nested server shape", () => {
  assert.equal(convertXrayConfig("{").value, null);
  assert.equal(convertXrayConfig(JSON.stringify({ outbounds: Array.from({ length: 33 }, () => ({})) })).value, null);
  const r = run([{ protocol: "vless", settings: { vnext: [] } }]);
  assert.equal(r.value, null);
  assert.ok(r.diagnostics.some(d => d.code === "unsupported_input_shape"));
});
