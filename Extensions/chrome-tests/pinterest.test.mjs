import test from "node:test";
import assert from "node:assert/strict";
import { boardIdFromHtml, feedPath, pinsFromFeed, parseBoardUrl, pinIdsFromHrefs, boardNameFromTitle, buildBoardImport } from "../chrome/lib/pinterest.js";

test("recognises board pages and nothing else", () => {
  assert.deepEqual(parseBoardUrl("https://www.pinterest.com/ana/refs/"), { user: "ana", board: "refs" });
  assert.deepEqual(parseBoardUrl("https://in.pinterest.com/a.b/dark-interiors/?invite_code=x"), { user: "a.b", board: "dark-interiors" });
  assert.deepEqual(parseBoardUrl("https://www.pinterest.co.uk/ana/shoes/section-x/"), { user: "ana", board: "shoes" });
  for (const u of ["https://www.pinterest.com/", "https://www.pinterest.com/ana/", "https://www.pinterest.com/pin/123/", "https://www.pinterest.com/ana/_saved/",
                   "https://example.com/ana/shoes/", "not a url"]) assert.equal(parseBoardUrl(u), null, u);
});

test("collects pin ids once each, in page order, ignoring other links", () => {
  const hrefs = ["/pin/111/", "/pin/222/?x=1", "/pin/111/", "https://www.pinterest.com/pin/2nuyxyqa/", "/ana/shoes/", "/pin/333", "/pin/", null, "/pins/999/"];
  assert.deepEqual(pinIdsFromHrefs(hrefs), ["111", "222", "2nuyxyqa", "333"]);
});

test("board names come from the page title", () => {
  assert.equal(boardNameFromTitle("refs | Pinterest"), "refs");
  assert.equal(boardNameFromTitle("Dark Interiors - Pinterest"), "Dark Interiors");
  assert.equal(boardNameFromTitle("", "my board"), "my board");
});

test("builds the import body, or nothing when there is nothing to import", () => {
  const body = buildBoardImport({ url: "https://www.pinterest.com/ana/dark-interiors/?x=1", title: "Dark Interiors | Pinterest", pinIds: ["1", "2"] });
  assert.deepEqual(body, { source: "pinterest", name: "Dark Interiors", url: "https://www.pinterest.com/ana/dark-interiors/", pinIds: ["1", "2"] });
  assert.equal(buildBoardImport({ url: "https://www.pinterest.com/ana/dark-interiors/", title: "x", pinIds: [] }), null);
  assert.equal(buildBoardImport({ url: "https://example.com/a/b", title: "x", pinIds: ["1"] }), null);
});

import { boardsFromAnchors, buildBoardBody, jobFromHash, parsePinCount } from "../chrome/lib/pinterest.js";

test("job nonce comes from the hash", () => {
  assert.equal(jobFromHash("#grails=0123456789abcdef0123456789abcdef"), "0123456789abcdef0123456789abcdef");
  assert.equal(jobFromHash("#grails=ABCDEF0123456789"), "abcdef0123456789");
  assert.equal(jobFromHash("#other"), null);
  assert.equal(jobFromHash(""), null);
});

test("pin counts read in every style", () => {
  assert.equal(parsePinCount("1,204 Pins"), 1204);
  assert.equal(parsePinCount("1.204 pins"), 1204);
  assert.equal(parsePinCount("12 Pins"), 12);
  assert.equal(parsePinCount("1.2k Pins"), 1200);
  assert.equal(parsePinCount("Interiors\n340 Pins\n2y"), 340);
  assert.equal(parsePinCount("Interiors"), null);
});

test("boards come out of a profile page's links, once each, in order", () => {
  const anchors = [
    { href: "/ana/interiors/", text: "Interiors\n340 Pins", cover: "https://i.pinimg.com/a.jpg" },
    { href: "/ana/interiors/?x=1", text: "again" },
    { href: "/ana/_saved/", text: "Saved" },
    { href: "/ana/", text: "Profile" },
    { href: "/other/board/", text: "Not hers" },
    { href: "/ana/dark-rooms/", text: "12 Pins" },
    { href: "/ana/pins/", text: "Pins" },
  ];
  const boards = boardsFromAnchors(anchors, "ana");
  assert.deepEqual(boards.map((b) => b.url), ["https://www.pinterest.com/ana/interiors/", "https://www.pinterest.com/ana/dark-rooms/"]);
  assert.deepEqual([boards[0].name, boards[0].count, boards[0].cover], ["Interiors", 340, "https://i.pinimg.com/a.jpg"]);
  assert.equal(boards[1].name, "dark rooms");                      // no title line: named from the link
  assert.equal(boards[1].count, 12);
});

test("a scrolled board becomes one import body, carrying the job", () => {
  const pins = [{ id: "1", image: "https://i.pinimg.com/236x/a.jpg" }, { id: "AbC" }];
  const body = buildBoardBody({ url: "https://www.pinterest.com/ana/interiors/?x=1", title: "Interiors | Pinterest", pins, jobId: "j1" });
  assert.deepEqual(body, { source: "pinterest", jobId: "j1", boards: [{ url: "https://www.pinterest.com/ana/interiors/", name: "Interiors", pins }] });
  assert.equal(buildBoardBody({ url: "https://www.pinterest.com/ana/interiors/", title: "x", pins: [] }), null);
  assert.equal(buildBoardBody({ url: "https://example.com/a/b", title: "x", pins }), null);
  assert.equal(buildBoardBody({ url: "https://www.pinterest.com/ana/b/", title: "x", pins }).jobId, undefined);
});


import { boardIdFromHtml as idFromHtml, feedPath as feedUrl, pinsFromFeed as fromFeed, boardNameFromTitle as nameFromTitle } from "../chrome/lib/pinterest.js";
test("a notification count and a generic title never become the board's name", () => {
  assert.equal(nameFromTitle("(25) Pinterest", "my secret board"), "my secret board");
  assert.equal(nameFromTitle("(3) Shoes | Pinterest", "x"), "Shoes");
  assert.equal(nameFromTitle("Pinterest", "interiors"), "interiors");
});
test("the board id is found the way the page embeds it", () => {
  assert.equal(idFromHtml('<script>"board_id\\",\\"4242\\""</script>'), "4242");
  assert.equal(idFromHtml('{"board_id":"777"}'), "777");
  assert.equal(idFromHtml("<html></html>"), null);
});
test("feed pages: the address carries the bookmark, and rows become pins with their biggest picture", () => {
  const first = feedUrl({ boardId: "9", pathname: "/ana/secret/" });
  assert.ok(first.startsWith("/resource/BoardFeedResource/get/?source_url=%2Fana%2Fsecret%2F&data="));
  assert.equal(JSON.parse(decodeURIComponent(first.split("data=")[1])).options.bookmarks, undefined);
  assert.deepEqual(JSON.parse(decodeURIComponent(feedUrl({ boardId: "9", pathname: "/a/b/", bookmark: "bm" }).split("data=")[1])).options.bookmarks, ["bm"]);
  const pins = fromFeed([{ type: "pin", id: 1, images: { "236x": { url: "s.jpg" }, orig: { url: "o.jpg" } } }, { type: "story", id: 2 }, { type: "pin", id: "3", images: { "236x": { url: "t.jpg" } } }, { type: "pin" }]);
  assert.deepEqual(pins, [{ id: "1", image: "o.jpg" }, { id: "3", image: "t.jpg" }]);
});
