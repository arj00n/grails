import test from "node:test";
import assert from "node:assert/strict";
import { StashClient, StashError } from "../chrome/lib/client.js";

function make(handler, settings = { token: "tok", port: 0 }) {
  const state = { ...settings };
  const calls = [];
  const client = new StashClient({
    fetchFn: async (url, opts) => { calls.push({ url, opts }); return handler(url, opts); },
    getSettings: async () => state,
    setSettings: async (p) => Object.assign(state, p),
  });
  return { client, calls, state };
}
const res = (status, body) => ({ ok: status >= 200 && status < 300, status, text: async () => JSON.stringify(body) });

test("sends the bearer token and JSON body", async () => {
  const { client, calls } = make(() => res(201, { ok: true, id: "I1", name: "x" }));
  const r = await client.save({ pageUrl: "https://a.com" });
  assert.equal(r.id, "I1");
  assert.equal(calls[0].url, "http://127.0.0.1:47823/api/v1/items");
  assert.equal(calls[0].opts.headers.Authorization, "Bearer tok");
  assert.equal(calls[0].opts.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].opts.body), { pageUrl: "https://a.com" });
});

test("scans nearby ports when the app moved, and remembers the one that answered", async () => {
  const { client, calls, state } = make((url) => {
    if (url.includes(":47825/")) return res(200, { ok: true, library: "Swish" });
    throw new TypeError("Failed to fetch");
  });
  const r = await client.ping();
  assert.equal(r.library, "Swish");
  assert.equal(state.port, 47825);
  assert.ok(calls.length >= 3);
  calls.length = 0;
  await client.ping();
  assert.equal(calls[0].url, "http://127.0.0.1:47825/api/v1/ping");   // tries the remembered port first
});

test("maps failures to specific errors", async () => {
  await assert.rejects(make(() => { throw new TypeError("nope"); }).client.ping(), (e) => e instanceof StashError && e.kind === "offline");
  await assert.rejects(make(() => res(401, { error: "x" })).client.ping(), (e) => e.kind === "unauthorized");
  await assert.rejects(make(() => res(403, { error: "Origin not allowed" })).client.ping(), (e) => e.kind === "forbidden");
  await assert.rejects(make(() => res(400, { error: "bad body" })).client.save({}), (e) => e.kind === "bad-request" && e.message === "bad body");
  await assert.rejects(make(() => res(502, { error: "download failed" })).client.save({}), (e) => e.kind === "server");
  await assert.rejects(make(() => res(200, {}), { token: "", port: 0 }).client.ping(), (e) => e.kind === "unauthorized");
});

test("an auth error stops the scan instead of trying every port", async () => {
  const { client, calls } = make(() => res(401, {}));
  await assert.rejects(client.ping());
  assert.equal(calls.length, 1);
});
