import test from "node:test";
import assert from "node:assert/strict";
import { buildPayload, cleanTitle, dataUrlToBase64, isDirectVideoUrl, updateRecents } from "../chrome/lib/payload.js";

test("image: http source is downloaded by Grails, with page context", () => {
  const p = buildPayload({ kind: "image", srcUrl: "https://cdn.x.com/a.jpg", pageUrl: "https://x.com/post", title: "  A\n  photo " });
  assert.deepEqual(p, { title: "A photo", pageUrl: "https://x.com/post", mediaUrl: "https://cdn.x.com/a.jpg" });
});

test("image: blob/data sources must carry bytes from the page", () => {
  assert.equal(buildPayload({ kind: "image", srcUrl: "blob:https://x.com/uuid", pageUrl: "https://x.com" }), null);
  const p = buildPayload({ kind: "image", srcUrl: "blob:https://x.com/uuid", dataBase64: "QUJD", pageUrl: "https://x.com" });
  assert.equal(p.dataBase64, "QUJD");
  assert.equal(p.mediaUrl, undefined);
});

test("video: direct file → mediaUrl; streaming → frame, poster, then page link", () => {
  assert.equal(buildPayload({ kind: "video", srcUrl: "https://v.x.com/clip.mp4?token=1", pageUrl: "https://x.com" }).mediaUrl, "https://v.x.com/clip.mp4?token=1");
  assert.equal(buildPayload({ kind: "video", srcUrl: "blob:https://x.com/1", dataBase64: "RlJBTUU=", pageUrl: "https://x.com" }).dataBase64, "RlJBTUU=");
  assert.equal(buildPayload({ kind: "video", srcUrl: "blob:https://x.com/1", posterUrl: "https://x.com/poster.jpg", pageUrl: "https://x.com" }).mediaUrl, "https://x.com/poster.jpg");
  const last = buildPayload({ kind: "video", srcUrl: "blob:https://x.com/1", pageUrl: "https://x.com/watch" });
  assert.deepEqual(last, { pageUrl: "https://x.com/watch" });
  assert.equal(buildPayload({ kind: "video", srcUrl: "blob:x" }), null);
});

test("link: saves the target as a link card and ignores non-http", () => {
  const p = buildPayload({ kind: "link", linkUrl: "https://dribbble.com/shots/1", pageUrl: "https://x.com", title: "Page title" });
  assert.deepEqual(p, { pageUrl: "https://dribbble.com/shots/1" });
  assert.equal(buildPayload({ kind: "link", linkUrl: "javascript:alert(1)" }), null);
  assert.equal(buildPayload({ kind: "link", linkUrl: "mailto:a@b.c" }), null);
});

test("page: title, url, optional snapshot, collection", () => {
  const p = buildPayload({ kind: "page", pageUrl: "https://a.com/x", title: "T", snapshotBase64: "U05BUA==", collectionId: "C1" });
  assert.deepEqual(p, { title: "T", collectionId: "C1", pageUrl: "https://a.com/x", snapshotBase64: "U05BUA==" });
  assert.equal(buildPayload({ kind: "page", pageUrl: "chrome://extensions" }), null);
  assert.equal(buildPayload({ kind: "nope" }), null);
});

test("helpers", () => {
  assert.equal(cleanTitle("   "), undefined);
  assert.equal(cleanTitle("x".repeat(400)).length, 300);
  assert.ok(isDirectVideoUrl("http://a/b.WEBM"));
  assert.ok(!isDirectVideoUrl("https://a/b.html"));
  assert.equal(dataUrlToBase64("data:image/jpeg;base64,QUJD"), "QUJD");
  assert.equal(dataUrlToBase64("nope"), null);
  const r = updateRecents([{ id: "a", name: "A" }, { id: "b", name: "B" }, { id: "c", name: "C" }], { id: "b", name: "B2" }, 3);
  assert.deepEqual(r.map((x) => x.id), ["b", "a", "c"]);
  assert.equal(updateRecents(Array.from({ length: 5 }, (_, i) => ({ id: "" + i, name: "" })), { id: "z", name: "Z" }).length, 5);
});

import { isXPage, statusUrl, upgradeTwimg } from "../chrome/lib/payload.js";

test("x: post links are recognised and normalised", () => {
  assert.equal(statusUrl("https://x.com/ana/status/123/photo/1?s=20"), "https://x.com/ana/status/123");
  assert.equal(statusUrl("https://twitter.com/ana/status/123"), "https://x.com/ana/status/123");
  assert.equal(statusUrl("https://x.com/i/web/status/123"), "https://x.com/i/status/123");
  assert.equal(statusUrl("https://x.com/ana"), null);
  assert.equal(statusUrl("https://example.com/ana/status/123"), null);
  assert.ok(isXPage("https://www.x.com/home"));
  assert.ok(!isXPage("https://example.com"));
});

test("x: pictures are saved at original size", () => {
  assert.equal(upgradeTwimg("https://pbs.twimg.com/media/ABC.jpg"), "https://pbs.twimg.com/media/ABC?format=jpg&name=orig");
  assert.equal(upgradeTwimg("https://pbs.twimg.com/media/ABC?format=png&name=small"), "https://pbs.twimg.com/media/ABC?format=png&name=orig");
  assert.equal(upgradeTwimg("https://pbs.twimg.com/profile_images/1/a.jpg"), "https://pbs.twimg.com/profile_images/1/a.jpg");
  assert.equal(buildPayload({ kind: "image", srcUrl: "https://pbs.twimg.com/media/ABC?format=jpg&name=360x360", pageUrl: "https://x.com/home" }).mediaUrl, "https://pbs.twimg.com/media/ABC?format=jpg&name=orig");
});
