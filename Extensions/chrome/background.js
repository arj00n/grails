import { StashClient, StashError } from "./lib/client.js";
import { buildBoardImport } from "./lib/pinterest.js";
import { buildPayload, dataUrlToBase64, isDirectVideoUrl, isXPage, menuTitleFor, statusUrl, updateRecents } from "./lib/payload.js";

const store = {
  async get() {
    const s = await chrome.storage.local.get({ token: "", port: 0, recents: [], lastSaved: [] });
    return s;
  },
  async set(patch) { await chrome.storage.local.set(patch); },
};

export const client = new StashClient({ getSettings: () => store.get(), setSettings: (p) => store.set(p) });

// ---- Context menus --------------------------------------------------------------------------------------------

async function rebuildMenus() {
  await chrome.contextMenus.removeAll();
  const { recents } = await store.get();
  const contexts = ["image", "video", "link", "page"];
  chrome.contextMenus.create({ id: "stash", title: "Save to Stash", contexts });
  chrome.contextMenus.create({ id: "stash:inbox", parentId: "stash", title: "Inbox", contexts });
  for (const c of recents) {
    chrome.contextMenus.create({ id: `stash:c:${c.id}`, parentId: "stash", title: c.name, contexts });
  }
}

chrome.runtime.onInstalled.addListener(rebuildMenus);
chrome.runtime.onStartup.addListener(rebuildMenus);
chrome.storage.onChanged.addListener((changes, area) => { if (area === "local" && changes.recents) rebuildMenus(); });

function kindFor(info) {
  if (info.mediaType === "image") return "image";
  if (info.mediaType === "video") return "video";
  if (info.linkUrl) return "link";
  return "page";
}

export async function handleMenuClick(info, tab) {
  const id = String(info.menuItemId);
  if (!id.startsWith("stash")) return;
  const collectionId = id.startsWith("stash:c:") ? id.slice(8) : undefined;
  const kind = kindFor(info);
  await saveFromTab({ kind, info, tab, collectionId });
}

chrome.contextMenus.onClicked.addListener((info, tab) => { handleMenuClick(info, tab); });

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command === "save-page") {
    const t = tab || (await chrome.tabs.query({ active: true, currentWindow: true }))[0];
    if (t) await saveFromTab({ kind: "page", info: { pageUrl: t.url }, tab: t });
  }
});

// ---- Gathering bytes the page can see but Stash can't download ------------------------------------------------

async function inPage(tab, frameId, fn, args) {
  try {
    const [r] = await chrome.scripting.executeScript({ target: { tabId: tab.id, frameIds: [frameId ?? 0] }, func: fn, args });
    return r?.result;
  } catch { return undefined; }
}

function pageFetchBase64(url) {
  return fetch(url).then((r) => r.blob()).then((b) => new Promise((resolve) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result).split("base64,")[1] || null);
    fr.onerror = () => resolve(null);
    fr.readAsDataURL(b);
  })).catch(() => null);
}

function pageVideoInfo(src) {
  const v = [...document.querySelectorAll("video")].find((el) => el.currentSrc === src || el.src === src) || document.querySelector("video");
  if (!v) return {};
  let frame = null;
  try {
    const c = document.createElement("canvas");
    c.width = v.videoWidth; c.height = v.videoHeight;
    c.getContext("2d").drawImage(v, 0, 0);
    frame = c.toDataURL("image/jpeg", 0.92).split("base64,")[1];
  } catch { /* cross-origin video taints the canvas */ }
  return { poster: v.poster || null, frame };
}

/** On X, videos and GIFs stream in pieces and can't be saved from the page: Stash reads the post itself instead. */
async function xPostFor({ kind, info, tab }) {
  if (!isXPage(tab?.url || info.pageUrl)) return null;
  if (kind === "link") return statusUrl(info.linkUrl);
  if (kind === "page") return statusUrl(tab?.url || info.pageUrl);
  if (kind !== "video") return null;
  const tapped = tab ? await inPage(tab, info.frameId, () => window.__stashLastTweet) : undefined;
  return statusUrl(tapped) || statusUrl(tab?.url || info.pageUrl);
}

async function saveFromTab({ kind, info, tab, collectionId, altClickImage }) {
  const post = await xPostFor({ kind, info, tab });
  if (post) {
    try {
      await client.importBoard({ source: "x", url: post });
      notify(tab, true, "Saving the post's media to Stash");
      return { ok: true };
    } catch (e) {
      notify(tab, false, e instanceof StashError ? e.message : String(e));
      return null;
    }
  }
  const ev = { kind, collectionId, pageUrl: tab?.url || info.pageUrl, title: tab?.title };
  if (kind === "image") {
    ev.srcUrl = info.srcUrl;
    if (info.srcUrl && !/^https?:/i.test(info.srcUrl) && tab) ev.dataBase64 = await inPage(tab, info.frameId, pageFetchBase64, [info.srcUrl]);
    if (altClickImage?.title) ev.title = altClickImage.title;
  } else if (kind === "video") {
    ev.srcUrl = info.srcUrl;
    if (tab && !isDirectVideoUrl(info.srcUrl)) {
      // streaming (blob:/MSE) video can't be downloaded: grab the current frame, or at least the poster
      const v = await inPage(tab, info.frameId, pageVideoInfo, [info.srcUrl]);
      if (v?.frame) ev.dataBase64 = v.frame; else if (v?.poster) ev.posterUrl = v.poster;
    }
  } else if (kind === "link") {
    ev.linkUrl = info.linkUrl;
  } else if (kind === "page" && tab?.windowId !== undefined) {
    try { ev.snapshotBase64 = dataUrlToBase64(await chrome.tabs.captureVisibleTab(tab.windowId, { format: "jpeg", quality: 85 })); } catch { /* no permission on this page */ }
  }
  const payload = buildPayload(ev);
  if (!payload) return notify(tab, false, "Nothing to save here.");
  try {
    const result = await client.save(payload);
    await rememberSaved(result, collectionId);
    notify(tab, true, result.duplicate ? "Already in Stash" : "Saved to Stash");
    return result;
  } catch (e) {
    notify(tab, false, e instanceof StashError ? e.message : String(e));
  }
}

async function rememberSaved(result, collectionId) {
  const { recents, lastSaved } = await store.get();
  const patch = { lastSaved: [{ id: result.id, name: result.name, kind: result.kind, at: Date.now() }, ...lastSaved].slice(0, 8) };
  if (collectionId) {
    const cols = await client.collections().catch(() => []);
    const c = cols.find((x) => x.id === collectionId);
    if (c) patch.recents = updateRecents(recents, c);
  }
  await store.set(patch);
}

function notify(tab, ok, text) {
  if (tab?.id !== undefined) chrome.tabs.sendMessage(tab.id, { type: "stash-toast", ok, text }).catch(() => {});
  chrome.action.setBadgeBackgroundColor({ color: ok ? "#30A46C" : "#E5484D" });
  chrome.action.setBadgeText({ text: ok ? "✓" : "!" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}

// ---- Messages from the content script and popup ---------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, respond) => {
  (async () => {
    if (msg.type === "save-image") {
      respond(await saveFromTab({ kind: "image", info: { srcUrl: msg.srcUrl, frameId: sender.frameId }, tab: sender.tab, altClickImage: { title: msg.title } }));
    } else if (msg.type === "save-page") {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      respond(tab ? await saveFromTab({ kind: "page", info: { pageUrl: tab.url }, tab, collectionId: msg.collectionId }) : null);
    } else if (msg.type === "board-collected") {
      const body = buildBoardImport({ url: msg.url, title: msg.title, pinIds: msg.pinIds });
      if (!body) { notify(sender.tab, false, "That doesn't look like a Pinterest board."); respond(null); return; }
      try {
        const r = await client.importBoard(body);
        notify(sender.tab, true, `Sent ${r.count} pins to Stash. It's importing them now.`);
        respond({ ok: true, count: r.count });
      } catch (e) {
        notify(sender.tab, false, e instanceof StashError ? e.message : String(e));
        respond({ ok: false, error: String(e.message || e) });
      }
    } else if (msg.type === "ping") {
      try { respond({ ok: true, ...(await client.ping()) }); } catch (e) { respond({ ok: false, kind: e.kind, error: e.message }); }
    } else if (msg.type === "collections") {
      try { respond({ ok: true, collections: await client.collections() }); } catch (e) { respond({ ok: false, error: e.message }); }
    }
  })();
  return true;
});

// Exposed for tests that drive the service worker over the DevTools protocol.
globalThis.__stash = { handleMenuClick, saveFromTab, client, menuTitleFor };
