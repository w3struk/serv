import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

// Loading by data URL keeps this repository's standalone .js ES module usable
// without adding a package-level module-type setting.
const source = await readFile(new URL("../../docs/converter/converter.js", import.meta.url), "utf8");
const { convertXrayConfig } = await import(`data:text/javascript,${encodeURIComponent(source)}`);
const id = "00000000-0000-4000-8000-000000000001";
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

test("converts flattened VLESS Encryption, Vision, TLS and XHTTP", () => {
  const r = run([base({ settings: { flow: "xtls-rprx-vision", encryption: "mlkem768x25519plus.native" }, xhttp: { host: "synthetic.invalid", headers: { "X-Test": "ok" } } })]);
  assert.equal(r.diagnostics.filter(d => d.severity === "fatal").length, 0);
  assert.deepEqual(r.value.outbounds[0], { type: "vless", tag: "client", server: "synthetic.invalid", server_port: 443, uuid: id, flow: "xtls-rprx-vision", encryption: "mlkem768x25519plus.native", tls: { enabled: true, server_name: "synthetic.invalid", utls: { enabled: true, fingerprint: "chrome" } }, transport: { type: "xhttp", path: "/unit", mode: "auto", x_padding_bytes: 1, host: "synthetic.invalid", headers: { "X-Test": "ok" } } });
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
  const r = run([base({ xhttp: { xPaddingObfsMode: true, xPaddingKey: "synthetic-key", xPaddingHeader: "X-Pad", xPaddingPlacement: "header", xPaddingMethod: "tokenish" }, streamSettings: { tlsSettings: { allowInsecure: true } } })]);
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

test("validates containers, preserves __proto__, and warns on allowInsecure", () => {
  for (const field of ["tlsSettings", "xhttpSettings"]) {
    const streamSettings = { network: "xhttp", security: "tls", [field]: null };
    assert.equal(run([base({ streamSettings })]).value, null);
  }
  assert.equal(run([base({ xhttp: { xmux: "bad" } })]).value, null);
  const headers = JSON.parse('{"__proto__":"synthetic"}');
  const r = run([base({ xhttp: { headers }, streamSettings: { network: "xhttp", security: "tls", tlsSettings: { serverName: "synthetic.invalid", allowInsecure: true }, xhttpSettings: { path: "/unit", mode: "auto", xPaddingBytes: 1, headers } } })]);
  assert.equal(r.value.outbounds[0].transport.headers["__proto__"], "synthetic");
  assert.equal(Object.prototype.hasOwnProperty.call(r.value.outbounds[0].transport.headers, "__proto__"), true);
  assert.ok(r.diagnostics.some(d => d.code === "unsupported_field"));
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

test("warns server-only fields and rejects decryption/server shape", () => {
  const warning = run([base({ xhttp: { scMaxBufferedPosts: 2 } })]);
  assert.ok(warning.diagnostics.some(d => d.code === "server_only_field"));
  assert.ok(warning.diagnostics.some(d => d.code === "server_only_field" && d.path.endsWith(".streamSettings.xhttpSettings")));
  const streamWarning = run([base({ streamSettings: {
    network: "xhttp",
    security: "tls",
    tlsSettings: { serverName: "synthetic.invalid" },
    xhttpSettings: { path: "/unit", mode: "auto", xPaddingBytes: 1 },
    serverName: "synthetic.invalid"
  } })]);
  assert.ok(streamWarning.diagnostics.some(d => d.code === "server_only_field" && d.path.endsWith(".streamSettings")));
  const rejected = run([{ ...base(), decryption: "none" }]);
  assert.equal(rejected.value, null);
  assert.ok(rejected.diagnostics.some(d => d.code === "server_input"));
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
