import { parseBoardUrl } from "./lib/pinterest.js";
const $ = (id) => document.getElementById(id);
const send = (msg) => chrome.runtime.sendMessage(msg);

let waiting = false;

function show({ dot, text, connect, actions }) {
  $("dot").className = "dot " + (dot || "");
  $("statusText").textContent = text;
  $("connect").hidden = !connect;
  $("actions").hidden = !actions;
}

async function refresh() {
  const r = await send({ type: "ping" });
  if (r?.ok) {
    waiting = false;
    show({ dot: "ok", text: r.library || "Connected", actions: true });
    const c = await send({ type: "collections" });
    const sel = $("collection");
    sel.length = 1;
    for (const col of (c?.collections || []).filter((x) => x.kind !== "folder")) sel.add(new Option(col.name, col.id));
    const { lastSaved } = await chrome.storage.local.get({ lastSaved: [] });
    $("recent").replaceChildren(...(lastSaved.length ? lastSaved : [null]).map((s) => {
      const li = document.createElement("li");
      if (!s) { li.className = "empty"; li.textContent = "Nothing yet"; return li; }
      const name = document.createElement("span"), kind = document.createElement("span");
      name.textContent = s.name; kind.textContent = s.kind === "link" ? "Link" : s.kind === "page" ? "Page" : "Image";
      li.append(name, kind);
      return li;
    }));
  } else if (r?.kind === "offline") {
    show({ dot: "bad", text: "Grails isn't running", connect: true });
    $("connectText").textContent = "Open Grails on this Mac, then connect.";
    $("connectButton").hidden = true;
  } else {
    show({ dot: "", text: waiting ? "Waiting for Grails" : "Not connected", connect: true });
    $("connectText").textContent = waiting ? "Click Allow in Grails." : "Connect this browser to Grails on this Mac.";
    $("connectButton").hidden = waiting;
  }
}

$("connectButton").addEventListener("click", async () => {
  waiting = true;
  await refresh();
  await send({ type: "pair" });             // Grails shows Allow; this resolves when it is answered
  await refresh();
});
$("importBoard").addEventListener("click", async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  await chrome.tabs.sendMessage(tab.id, { type: "collect-board" }).catch(() => {});
  window.close();           // progress shows on the page itself
});
$("savePage").addEventListener("click", async () => {
  $("savePage").disabled = true;
  await send({ type: "save-page", collectionId: $("collection").value || undefined });
  $("savePage").disabled = false;
  await refresh();
});
(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  $("board").hidden = !(tab?.url && parseBoardUrl(tab.url));
})();
refresh();
// while it isn't connected, notice when Grails answers (the extension also asks by itself)
setInterval(() => { if (!$("connect").hidden) refresh(); }, 2000);
