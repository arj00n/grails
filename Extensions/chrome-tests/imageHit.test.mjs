import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const sandbox = {};
vm.runInNewContext(fs.readFileSync(new URL("../chrome/lib/imageHit.js", import.meta.url), "utf8"), sandbox);
const { cssImageURLs, srcsetCandidates, chooseImageURL, pickHit, altClick } = sandbox;
// Arrays built inside the vm have that realm's prototype; copy them before deepEqual.
const cssURLs = (value) => [...cssImageURLs(value)];

const pin = "https://i.pinimg.com/736x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg";
const srcset = [
  "https://i.pinimg.com/236x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 1x",
  "https://i.pinimg.com/474x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 2x",
  "https://i.pinimg.com/736x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 3x",
  "https://i.pinimg.com/originals/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 4x",
].join(", ");

test("css backgrounds: quotes, image-set, and a gradient in front of the picture", () => {
  assert.deepEqual(cssURLs('url("https://i.pinimg.com/736x/a.jpg")'), ["https://i.pinimg.com/736x/a.jpg"]);
  assert.deepEqual(cssURLs("url('https://i.pinimg.com/a.jpg')"), ["https://i.pinimg.com/a.jpg"]);
  assert.deepEqual(cssURLs("none"), []);
  assert.deepEqual(
    cssURLs('linear-gradient(red, blue), url("https://i.pinimg.com/a.jpg")'),
    ["https://i.pinimg.com/a.jpg"],
  );
  assert.deepEqual(
    cssURLs('image-set(url("https://i.pinimg.com/236x/a.jpg") 1x, url("https://i.pinimg.com/736x/a.jpg") 2x)'),
    ["https://i.pinimg.com/236x/a.jpg", "https://i.pinimg.com/736x/a.jpg"],
  );
});

test("srcset puts the largest Pinterest candidate first", () => {
  assert.equal(srcsetCandidates(srcset)[0], "https://i.pinimg.com/originals/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg");
  assert.equal(
    srcsetCandidates("https://cdn.test/a.jpg 236w, https://cdn.test/b.jpg 736w")[0],
    "https://cdn.test/b.jpg",
  );
});

test("Pinterest 4x originals without a file extension are not the saved URL", () => {
  // Live pin srcset. The 4x originals path with no extension 403s. Open-image-in-new-tab
  // uses the jpeg the browser actually showed (736x), or the src jpeg when currentSrc isn't set.
  const set = [
    "https://i.pinimg.com/236x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 1x",
    "https://i.pinimg.com/474x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 2x",
    "https://i.pinimg.com/736x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg 3x",
    "https://i.pinimg.com/originals/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89 4x",
  ].join(", ");
  const jpeg = "https://i.pinimg.com/736x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg";
  assert.equal(chooseImageURL({ currentSrc: "", src: "https://i.pinimg.com/236x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg", srcset: set }), jpeg);
  assert.equal(chooseImageURL({ currentSrc: "blob:https://www.pinterest.com/uuid", src: "", srcset: set }), jpeg);
  assert.equal(chooseImageURL({ currentSrc: jpeg, src: "https://i.pinimg.com/236x/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg", srcset: set }), jpeg);
});

test("Option held counts even when the click event's altKey is false", () => {
  assert.equal(altClick({ altKey: true, button: 0 }), true);
  assert.equal(altClick({ altKey: false, button: 0 }, true), true);
  assert.equal(altClick({ altKey: false, altState: true, button: 0 }), true);
  assert.equal(altClick({ altKey: true, metaKey: true, button: 0 }), false);
  assert.equal(altClick({ altKey: true, ctrlKey: true, button: 0 }), false);
  assert.equal(altClick({ altKey: true, shiftKey: true, button: 0 }), false);
  assert.equal(altClick({ altKey: true, button: 2 }), false);
  assert.equal(altClick({ altKey: false, button: 0 }), false);
});

test("a displayed image is kept; an empty or data src defers to srcset", () => {
  assert.equal(chooseImageURL({ currentSrc: pin, src: "https://i.pinimg.com/236x/a.jpg", srcset }), pin);
  assert.equal(
    chooseImageURL({ currentSrc: "", src: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", srcset }),
    "https://i.pinimg.com/originals/34/94/d4/3494d4c535ea191d0da3cb91d2ac2a89.jpg",
  );
  assert.equal(
    chooseImageURL({ backgrounds: ["https://i.pinimg.com/236x/a.jpg", "https://i.pinimg.com/736x/a.jpg"] }),
    "https://i.pinimg.com/736x/a.jpg",
  );
});

test("the pin under the cursor beats the icon on top of it and a page-sized wash", () => {
  const view = 1920 * 1080;
  const hit = pickHit([
    { url: pin, title: "lamp", area: 221 * 295, kind: "img" },
    { url: "https://s.pinimg.com/icon.svg", title: "", area: 24 * 24, kind: "img" },
    { url: "https://example.com/wash.jpg", title: "", area: view, kind: "bg" },
  ], view);
  assert.equal(hit.url, pin);
  assert.equal(hit.title, "lamp");
});

test("a background pin still counts when there is no img", () => {
  const hit = pickHit([
    { url: "https://i.pinimg.com/474x/a.jpg", title: "", area: 236 * 300, kind: "bg" },
  ], 1920 * 1080);
  assert.equal(hit.url, "https://i.pinimg.com/474x/a.jpg");
});

test("a data placeholder loses to the real background under the same click", () => {
  const hit = pickHit([
    { url: "data:image/gif;base64,R0lGODlhAQABAAAAACw=", title: "", area: 221 * 295, kind: "img" },
    { url: "https://i.pinimg.com/736x/a.jpg", title: "", area: 221 * 295, kind: "bg" },
  ], 1920 * 1080);
  assert.equal(hit.url, "https://i.pinimg.com/736x/a.jpg");
});

test("a full-page background is the picture when nothing else is under the cursor", () => {
  const view = 800 * 600;
  const hit = pickHit([{ url: "https://cdn.test/hero.jpg", title: "", area: view, kind: "bg" }], view);
  assert.equal(hit.url, "https://cdn.test/hero.jpg");
});

test("only a click on a content-sized picture is stopped", () => {
  const listeners = {};
  const img = {
    nodeType: 1,
    tagName: "IMG",
    parentElement: null,
    querySelectorAll: () => [],
    getBoundingClientRect: () => ({ left: 0, top: 0, right: 200, bottom: 200, width: 200, height: 200 }),
  };
  const page = {
    window: {
      innerWidth: 1200,
      innerHeight: 800,
      addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn); },
    },
    document: {
      elementsFromPoint: () => [img],
      querySelectorAll: () => [img],
    },
  };
  vm.runInNewContext(fs.readFileSync(new URL("../chrome/lib/altStop.js", import.meta.url), "utf8"), page);
  function gesture(type, extra = {}) {
    return {
      type,
      altKey: true, metaKey: false, ctrlKey: false, shiftKey: false, button: 0,
      clientX: 20, clientY: 20, target: img,
      getModifierState: () => false,
      stopped: false,
      preventDefault() { this.stopped = true; },
      stopPropagation() { this.stopped = true; },
      stopImmediatePropagation() { this.stopped = true; },
      ...extra,
    };
  }
  const down = gesture("pointerdown");
  for (const fn of listeners.pointerdown) fn(down);
  assert.equal(down.stopped, false);
  const mouse = gesture("mousedown");
  for (const fn of listeners.mousedown) fn(mouse);
  assert.equal(mouse.stopped, false);

  const click = gesture("click");
  for (const fn of listeners.click) fn(click);
  assert.equal(click.stopped, true);

  const miss = gesture("click", {
    clientX: 900, clientY: 900, stopped: false,
    preventDefault() { this.stopped = true; },
    stopPropagation() { this.stopped = true; },
    stopImmediatePropagation() { this.stopped = true; },
  });
  page.document.elementsFromPoint = () => [];
  for (const fn of listeners.click) fn(miss);
  assert.equal(miss.stopped, false);
});
