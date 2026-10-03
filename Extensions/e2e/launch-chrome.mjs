import { spawn } from "node:child_process";
import fs from "node:fs";
const ext = new URL("../chrome", import.meta.url).pathname;
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", "--remote-debugging-pipe", "--remote-debugging-port=9333", "--enable-unsafe-extension-debugging",
  "--user-data-dir=/private/tmp/stash-chrome-profile", "--no-first-run", "--no-default-browser-check", "http://127.0.0.1:8765/index.html",
], { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"], detached: true });
const toChrome = chrome.stdio[3], fromChrome = chrome.stdio[4];
let buf = "";
const waiters = new Map();
fromChrome.on("data", (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf("\0")) >= 0) {
    const msg = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
    if (msg.id && waiters.has(msg.id)) { waiters.get(msg.id)(msg); waiters.delete(msg.id); }
  }
});
let n = 0;
const send = (method, params) => new Promise((res) => { const id = ++n; waiters.set(id, res); toChrome.write(JSON.stringify({ id, method, params }) + "\0"); });
await new Promise((r) => setTimeout(r, 3000));
const r = await send("Extensions.loadUnpacked", { path: ext });
console.log("loadUnpacked ->", JSON.stringify(r));
fs.writeFileSync("/private/tmp/stash-e2e/extid", r.result?.id || "");
await new Promise((r) => setTimeout(r, 120000));
chrome.kill();
