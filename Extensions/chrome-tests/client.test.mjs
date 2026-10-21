import test from "node:test";
import assert from "node:assert/strict";
import { GrailsClient, GrailsError } from "../chrome/lib/client.js";

function make(handler, settings = { token: "tok", port: 0 }) {
  const state = { ...settings };
  const calls = [];
  const client = new GrailsClient({
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
    if (url.includes(":47825/")) return res(200, { ok: true, library: "Studio" });
    throw new TypeError("Failed to fetch");
  });
  const r = await client.ping();
  assert.equal(r.library, "Studio");
  assert.equal(state.port, 47825);
  assert.ok(calls.length >= 3);
  calls.length = 0;
  await client.ping();
  assert.equal(calls[0].url, "http://127.0.0.1:47825/api/v1/ping");   // tries the remembered port first
});

test("maps failures to specific errors", async () => {
  await assert.rejects(make(() => { throw new TypeError("nope"); }).client.ping(), (e) => e instanceof GrailsError && e.kind === "offline");
  await assert.rejects(make(() => res(401, { error: "x" })).client.ping(), (e) => e.kind === "unauthorized");
  await assert.rejects(make(() => res(403, { error: "Origin not allowed" })).client.ping(), (e) => e.kind === "forbidden");
  await assert.rejects(make(() => res(400, { error: "bad body" })).client.save({}), (e) => e.kind === "bad-request" && e.message === "bad body");
  await assert.rejects(make(() => res(502, { error: "download failed" })).client.save({}), (e) => e.kind === "server");
  await assert.rejects(make(() => res(200, {}), { token: "", port: 0 }).client.ping(), (e) => e.kind === "unauthorized");
});

test("an auth error stops the scan instead of trying every port", async () => {
  const { client, calls } = make(() => res(401, {}));
  await assert.rejects(client.ping());
  assert.equal(calls.filter((c) => c.url.includes("/api/v1/ping")).length, 1);
});

test("a code Grails no longer knows is forgotten and the extension asks to pair again", async () => {
  const { client, calls, state } = make((url) => (url.endsWith("/api/v1/pair") ? res(202, { requestId: "r1" }) : url.includes("/api/v1/pair/") ? res(403, {}) : res(401, {})));
  await assert.rejects(client.ping(), (e) => e instanceof GrailsError && e.kind === "unauthorized");
  assert.equal(state.token, "");
  await new Promise((r) => setTimeout(r, 20));
  assert.ok(calls.some((c) => c.url.endsWith("/api/v1/pair") && c.opts.method === "POST"));
});

test("importBoard posts the pin ids to /api/v1/imports", async () => {
  const { client, calls } = make(() => res(202, { ok: true, count: 3 }));
  const r = await client.importBoard({ source: "pinterest", name: "x", pinIds: ["1", "2", "3"] });
  assert.equal(r.count, 3);
  assert.equal(calls[0].url, "http://127.0.0.1:47823/api/v1/imports");
  assert.equal(calls[0].opts.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].opts.body).pinIds, ["1", "2", "3"]);
});

test("pairing asks, waits for Allow, and stores the token it is given", async () => {
  let polls = 0;
  const { client, calls, state } = make((url, opts) => {
    if (url.endsWith("/api/v1/pair") && opts.method === "POST") return res(202, { requestId: "r1" });
    if (url.endsWith("/api/v1/pair/r1")) { polls += 1; return polls < 3 ? res(202, { ok: "pending" }) : res(200, { token: "fresh-token" }); }
    return res(404, {});
  }, { token: "", port: 0 });
  const token = await client.requestPairing({ sleep: async () => {}, pollMs: 0 });
  assert.equal(token, "fresh-token");
  assert.equal(state.token, "fresh-token");
  assert.equal(polls, 3);
  assert.equal(calls[0].opts.headers, undefined);                    // no token is sent while asking
});

test("pairing says so when it is refused or the app is not there", async () => {
  const refused = make((url, opts) => (opts.method === "POST" ? res(202, { requestId: "r2" }) : res(403, { error: "no" })), { token: "", port: 0 });
  await assert.rejects(() => refused.client.requestPairing({ sleep: async () => {}, pollMs: 0 }), (e) => e.kind === "forbidden");
  const away = make(() => { throw new TypeError("Failed to fetch"); }, { token: "", port: 0 });
  await assert.rejects(() => away.client.requestPairing({ sleep: async () => {} }), (e) => e.kind === "offline");
  const busy = make(() => res(429, {}), { token: "", port: 0 });
  await assert.rejects(() => busy.client.requestPairing({ sleep: async () => {} }), (e) => e.status === 429);
});

test("job calls go to the job's own routes", async () => {
  const { client, calls } = make(() => res(200, { ok: true }));
  await client.job("n1"); await client.jobBoards("n1", [{ url: "u", name: "x" }]); await client.jobProgress("n1", "b", 5); await client.jobDone("n1");
  assert.deepEqual(calls.map((c) => c.url.replace(/^http:\/\/127\.0\.0\.1:\d+/, "")), ["/api/v1/jobs/n1", "/api/v1/jobs/n1/boards", "/api/v1/jobs/n1/progress", "/api/v1/jobs/n1/done"]);
  assert.deepEqual(JSON.parse(calls[2].opts.body), { board: "b", scrolled: 5 });
});
