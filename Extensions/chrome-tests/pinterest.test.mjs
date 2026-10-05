import test from "node:test";
import assert from "node:assert/strict";
import { parseBoardUrl, pinIdsFromHrefs, boardNameFromTitle, buildBoardImport } from "../chrome/lib/pinterest.js";

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
