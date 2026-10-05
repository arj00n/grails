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
    if (!token) throw new GrailsError("unauthorized", "Paste the pairing code from Grails ▸ Settings ▸ Extensions.", 401);
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
      if (res.status === 401) throw new GrailsError("unauthorized", "Grails didn't accept the pairing code. Copy it again from Settings ▸ Extensions.", 401);
      if (res.status === 403) throw new GrailsError("forbidden", message, 403);
      if (res.status >= 500) throw new GrailsError("server", message, res.status);
      throw new GrailsError("bad-request", message, res.status);
    }
    throw new GrailsError("offline", "Grails isn't running. Open the app and try again.", 0);
  }

  ping() { return this._request("GET", "/api/v1/ping"); }
  collections() { return this._request("GET", "/api/v1/collections"); }
  save(payload) { return this._request("POST", "/api/v1/items", payload); }
  importBoard(body) { return this._request("POST", "/api/v1/imports", body); }
}
