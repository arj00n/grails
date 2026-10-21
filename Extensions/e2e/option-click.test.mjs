// Option-click an image in real Chromium with the unpacked extension loaded.
// Branded Chrome ignores --load-extension, so Playwright starts Chrome and the test
// installs the extension through the DevTools Extensions.loadUnpacked command.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import http from "node:http";
import { chromium } from "playwright";

const extensionDir = path.resolve(import.meta.dirname, "../chrome");
const hero = path.resolve(import.meta.dirname, "hero.png");

function serve(root) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    if (url.pathname === "/hero.png") {
      res.writeHead(200, { "content-type": "image/png" });
      res.end(fs.readFileSync(hero));
      return;
    }
    const file = path.join(root, decodeURIComponent(url.pathname));
    if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end("missing");
      return;
    }
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(fs.readFileSync(file));
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({ server, origin: `http://127.0.0.1:${port}` });
    });
  });
}

async function launch() {
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), "grails-option-click-"));
  const context = await chromium.launchPersistentContext(userData, {
    channel: "chrome",
    headless: true,
    ignoreDefaultArgs: ["--disable-extensions"],
    args: [
      "--enable-unsafe-extension-debugging",
      "--no-first-run",
      "--no-default-browser-check",
    ],
  });
  const session = await context.browser().newBrowserCDPSession();
  const loaded = await session.send("Extensions.loadUnpacked", { path: extensionDir });
  assert.equal(typeof loaded.id, "string");
  if (!context.serviceWorkers().length) {
    await context.waitForEvent("serviceworker", { timeout: 15000 });
  }
  return {
    context,
    async close() {
      await context.close();
      fs.rmSync(userData, { recursive: true, force: true });
    },
  };
}

async function toastText(page) {
  const session = await page.context().newCDPSession(page);
  try {
    const { root } = await session.send("DOM.getDocument", { pierce: true, depth: -1 });
    const texts = [];
    const walk = (node) => {
      if (node.nodeValue) texts.push(node.nodeValue);
      for (const child of node.children || []) walk(child);
      for (const shadow of node.shadowRoots || []) walk(shadow);
    };
    walk(root);
    return texts.join(" ");
  } finally {
    await session.detach();
  }
}

async function optionClick(page, selector) {
  await page.keyboard.down("Alt");
  try {
    await page.locator(selector).click();
  } finally {
    await page.keyboard.up("Alt");
  }
}

test("option-click saves on a plain page and does not open a page-handled pin", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "grails-option-pages-"));
  fs.writeFileSync(path.join(root, "plain.html"), `<!doctype html>
<html><head><title>Plain photo</title></head>
<body><img id="pic" src="/hero.png" width="320" height="200" alt="Hero photo"></body></html>`);
  fs.writeFileSync(path.join(root, "pin.html"), `<!doctype html>
<html><head><title>A pin</title></head>
<body>
<a id="pin" href="/opened.html"><img id="pic" src="/hero.png" width="320" height="200" alt="Lamp"></a>
<script>
  // pointerdown and mousedown stay passive (0.2.8); only the click is the save gesture.
  window.__opened = "";
  const mark = (from) => { if (!window.__opened) window.__opened = from; };
  window.addEventListener("click", () => { mark("window-click"); location.href = "/opened.html"; }, true);
  document.addEventListener("click", () => { mark("document-click"); location.href = "/opened.html"; }, true);
  document.getElementById("pin").addEventListener("click", () => { mark("element-click"); location.href = "/opened.html"; });
</script>
</body></html>`);
  fs.writeFileSync(path.join(root, "opened.html"), "<!doctype html><title>opened</title><p>opened</p>");

  const { server, origin } = await serve(root);
  const browser = await launch();
  try {
    const plain = await browser.context.newPage();
    await plain.goto(`${origin}/plain.html`, { waitUntil: "load" });
    await optionClick(plain, "#pic");
    await plain.waitForSelector("#__grails_toast", { state: "attached", timeout: 8000 });
    assert.match(await toastText(plain), /Grails/);
    assert.equal(new URL(plain.url()).pathname, "/plain.html");

    const pin = await browser.context.newPage();
    await pin.goto(`${origin}/pin.html`, { waitUntil: "load" });
    await optionClick(pin, "#pic");
    await pin.waitForSelector("#__grails_toast", { state: "attached", timeout: 8000 });
    assert.match(await toastText(pin), /Grails/);
    assert.equal(new URL(pin.url()).pathname, "/pin.html");
    assert.equal(await pin.evaluate(() => window.__opened), "");
  } finally {
    await browser.close();
    server.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
});
