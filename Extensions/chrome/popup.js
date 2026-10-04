import { parseBoardUrl } from "./lib/pinterest.js";
const $ = (id) => document.getElementById(id);
const send = (msg) => chrome.runtime.sendMessage(msg);

async function refresh() {
  const { token, lastSaved } = await chrome.storage.local.get({ token: "", lastSaved: [] });
  $("token").value = token;
  const r = await send({ type: "ping" });
  const connected = r?.ok;
  $("dot").className = "dot " + (connected ? "ok" : "bad");
  $("status").textContent = connected ? `Connected · ${r.library || "Stash"}` : r?.kind === "offline" ? "Stash isn't running" : "Not connected";
  $("pair").hidden = connected;
  $("actions").hidden = !connected;
  $("error").textContent = connected || !token ? "" : r?.error || "";
  if (connected) {
    const c = await send({ type: "collections" });
    const sel = $("collection");
    sel.length = 1;
    for (const col of (c?.collections || []).filter((x) => x.kind !== "folder")) sel.add(new Option(col.name, col.id));
    $("recent").replaceChildren(...lastSaved.map((s) => Object.assign(document.createElement("li"), { textContent: `${s.kind === "link" ? "🔗" : "🖼"} ${s.name}` })));
  }
}

$("connect").addEventListener("click", async () => {
  await chrome.storage.local.set({ token: $("token").value.trim() });
  await $("importBoard").addEventListener("click", async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  await chrome.tabs.sendMessage(tab.id, { type: "collect-board" }).catch(() => {});
  window.close();           // progress shows on the page itself
});
(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  $("board").hidden = !(tab?.url && parseBoardUrl(tab.url));
})();
refresh();
});
$("savePage").addEventListener("click", async () => {
  $("savePage").disabled = true;
  await send({ type: "save-page", collectionId: $("collection").value || undefined });
  $("savePage").disabled = false;
  await refresh();
});
refresh();
