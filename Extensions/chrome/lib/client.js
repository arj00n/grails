import { DEFAULT_PORT, PORT_SPAN } from "./payload.js";

export class GrailsError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.kind = kind;     // "offline" | "unauthorized" | "forbidden" | "bad-request" | "server"
    this.status = status;
  }
}

/** Talks to the Grails app on 127.0.0.1. `fetchFn` and `storage` are injected so this runs under Node in tests. */
export class GrailsClient {
  constructor({ fetchFn = globalThis.fetch.bind(globalThis), getSettings, setSettings }) {
    this.fetchFn = fetchFn;
    this.getSettings = getSettings;
    this.setSettings = setSettings;
  }

  async _url(path, port) {
    return `http://127.0.0.1:${port}${path}`;
  }

  async _request(method, path, body) {
    const { token, port } = await this.getSettings();
    if (!token) throw new GrailsError("unauthorized", "Not connected to Grails yet.", 401);
    const ports = [port || DEFAULT_PORT];
    for (let p = DEFAULT_PORT; p < DEFAULT_PORT + PORT_SPAN; p++) if (!ports.includes(p)) ports.push(p);
    let lastNetworkError;
    for (const p of ports) {
      let res;
      try {
        res = await this.fetchFn(await this._url(path, p), {
          method,
          headers: { Authorization: `Bearer ${token}`, ...(body ? { "Content-Type": "application/json" } : {}) },
          body: body ? JSON.stringify(body) : undefined,
        });
      } catch (e) {
        lastNetworkError = e;          // nothing listening on this port: try the next
        continue;
      }
      if (p !== port) await this.setSettings({ port: p });
      const text = await res.text();
      let json = {};
      try { json = text ? JSON.parse(text) : {}; } catch { /* non-JSON error page */ }
      if (res.ok) return json;
      const message = json.error || `Grails answered ${res.status}`;
      if (res.status === 401) {
        // the app made a new code (reinstalled, or its settings were reset): forget the old one and ask to pair again (the person clicks Allow)
        await this.setSettings({ token: "" });
        this.requestPairing().catch(() => {});
        throw new GrailsError("unauthorized", "Grails has a new pairing code. Click Allow in the app to reconnect.", 401);
      }
      if (res.status === 403) throw new GrailsError("forbidden", message, 403);
      if (res.status >= 500) throw new GrailsError("server", message, res.status);
      throw new GrailsError("bad-request", message, res.status);
    }
    throw new GrailsError("offline", "Grails isn't running. Open the app and try again.", 0);
  }

  ping() { return this._request("GET", "/api/v1/ping"); }

  /**
   * Asks Grails to pair: the app shows "Chrome wants in" and the person clicks Allow; no code is copied. Resolves with the token
   * (already stored), or throws when it is refused, times out, or the app isn't running.
   */
  async requestPairing({ timeoutMs = 120000, pollMs = 1000, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
    const { port } = await this.getSettings();
    const ports = [port || DEFAULT_PORT];
    for (let p = DEFAULT_PORT; p < DEFAULT_PORT + PORT_SPAN; p++) if (!ports.includes(p)) ports.push(p);
    let base = null, requestId = null;
    for (const p of ports) {
      try {
        const res = await this.fetchFn(`http://127.0.0.1:${p}/api/v1/pair`, { method: "POST" });
        if (res.status === 202) { base = p; requestId = (JSON.parse(await res.text())).requestId; break; }
        if (res.status === 429) throw new GrailsError("bad-request", "Another request is waiting in Grails.", 429);
      } catch (e) { if (e instanceof GrailsError) throw e; }
    }
    if (!base) throw new GrailsError("offline", "Grails isn't running. Open the app and try again.", 0);
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const res = await this.fetchFn(`http://127.0.0.1:${base}/api/v1/pair/${requestId}`, { method: "GET" });
      if (res.status === 200) {
        const { token } = JSON.parse(await res.text());
        await this.setSettings({ token, port: base });
        return token;
      }
      if (res.status === 403) throw new GrailsError("forbidden", "Grails didn't allow it.", 403);
      await sleep(pollMs);
    }
    throw new GrailsError("offline", "Nobody answered in Grails.", 0);
  }

  job(nonce) { return this._request("GET", `/api/v1/jobs/${nonce}`); }
  jobBoards(nonce, boards) { return this._request("POST", `/api/v1/jobs/${nonce}/boards`, { boards }); }
  jobProgress(nonce, board, scrolled) { return this._request("POST", `/api/v1/jobs/${nonce}/progress`, { board, scrolled }); }
  jobDone(nonce) { return this._request("POST", `/api/v1/jobs/${nonce}/done`, {}); }
  collections() { return this._request("GET", "/api/v1/collections"); }
  save(payload) { return this._request("POST", "/api/v1/items", payload); }
  importBoard(body) { return this._request("POST", "/api/v1/imports", body); }
}
