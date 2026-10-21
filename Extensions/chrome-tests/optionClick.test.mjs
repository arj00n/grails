// Chrome delivers one DOM event to MAIN-world and isolated-world listeners on the same
// window list, in registration order. altStop.js is registered first (MAIN). The isolated
// save listener in content.js is registered after it.
// Anything that is not the save gesture is passive: no preventDefault, no stopPropagation.
// The save gesture is a click on a content-sized picture that is not inside a link.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const imageHit = fs.readFileSync(new URL("../chrome/lib/imageHit.js", import.meta.url), "utf8");
const altStop = fs.readFileSync(new URL("../chrome/lib/altStop.js", import.meta.url), "utf8");
const content = fs.readFileSync(new URL("../chrome/content.js", import.meta.url), "utf8");

function element(tag, rect, extra = {}) {
  const node = {
    nodeType: 1,
    tagName: tag,
    alt: extra.alt || "",
    currentSrc: extra.src || "",
    parentElement: extra.parent || null,
    querySelectorAll: extra.query || (() => []),
    querySelector: extra.queryOne || (() => null),
    getAttribute(name) {
      if (name === "src") return extra.src || "";
      return "";
    },
    getBoundingClientRect: () => rect,
    closest: () => null,
  };
  return node;
}

const picture = (label, src) => element("IMG", { left: 40, top: 80, right: 360, bottom: 280, width: 320, height: 200 }, { alt: label, src });

// Unrelated pages. The picture is one element; the other target is what an option-click
// must not steal (a link, a paragraph, a code block).
const sites = {
  wiki: {
    href: "https://en.wikipedia.org/wiki/Grail",
    picture: picture("Grail", "https://upload.wikimedia.org/grail.jpg"),
    other: element("A", { left: 40, top: 40, right: 120, bottom: 58, width: 80, height: 18 }),
    otherAt: { x: 60, y: 48 },
  },
  news: {
    href: "https://www.reuters.com/world/story",
    picture: picture("Daily", "https://cdn.reuters.com/daily.jpg"),
    other: element("P", { left: 40, top: 320, right: 640, bottom: 360, width: 600, height: 40 }),
    otherAt: { x: 80, y: 340 },
  },
  code: {
    href: "https://github.com/grails/example",
    picture: picture("Avatar", "https://avatars.githubusercontent.com/u/1"),
    other: element("PRE", { left: 40, top: 400, right: 700, bottom: 520, width: 660, height: 120 }),
    otherAt: { x: 80, y: 440 },
  },
  pin: {
    href: "https://www.pinterest.com/pin/1",
    picture: picture("Lamp", "https://i.pinimg.com/736x/lamp.jpg"),
    other: element("A", { left: 40, top: 300, right: 200, bottom: 320, width: 160, height: 20 }),
    otherAt: { x: 80, y: 310 },
  },
};

function harness(site, extras = []) {
  const listeners = [];
  const messages = [];
  const targets = [site.picture, site.other, ...extras];
  const document = {
    title: site.href,
    documentElement: {},
    elementsFromPoint: (x, y) => {
      const hits = [];
      for (const el of targets) {
        const r = el.getBoundingClientRect();
        if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) hits.push(el);
      }
      return hits;
    },
    querySelectorAll: (sel) => (sel === "img" ? targets.filter((el) => el.tagName === "IMG") : []),
    addEventListener: (type, fn) => { listeners.push({ target: "document", type, fn }); },
    getElementById: () => null,
  };
  const window = {
    innerWidth: 1200,
    innerHeight: 800,
    addEventListener: (type, fn) => { listeners.push({ target: "window", type, fn }); },
  };
  window.top = window;
  const main = { window, document, URL, console };
  vm.runInNewContext(altStop, main);
  const isolated = {
    window, document, URL, console,
    location: { href: site.href, hash: "" },
    performance: { now: () => 100 },
    chrome: {
      runtime: {
        sendMessage: (msg) => { messages.push({ type: msg.type, srcUrl: msg.srcUrl, title: msg.title }); },
        onMessage: { addListener() {} },
      },
    },
    setTimeout, clearTimeout, requestAnimationFrame() {},
  };
  vm.runInNewContext(imageHit, isolated);
  vm.runInNewContext(content, isolated);

  const mark = (event) => { event.pageHandled = true; };
  for (const type of ["pointerdown", "mousedown", "click"]) {
    listeners.push({ target: "document", type, fn: mark });
    listeners.push({ target: "element", type, fn: mark });
    listeners.push({ target: "window", type, fn: mark });
  }

  function fire(type, x, y, target, overrides = {}) {
    const event = {
      type, altKey: true, metaKey: false, ctrlKey: false, shiftKey: false, button: 0,
      clientX: x, clientY: y, target,
      getModifierState: () => false,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.propagationStopped = true; },
      stopImmediatePropagation() { this.immediateStopped = true; this.propagationStopped = true; },
      ...overrides,
    };
    const order = ["window", "document", "element"];
    for (const name of order) {
      for (const listener of listeners) {
        if (listener.target !== name || listener.type !== type) continue;
        listener.fn(event);
        if (event.immediateStopped) return event;
      }
      if (event.propagationStopped) return event;
    }
    return event;
  }

  return { messages, fire };
}

function assertPassive(event, name) {
  assert.equal(event.defaultPrevented, undefined, name);
  assert.equal(event.propagationStopped, undefined, name);
  assert.equal(event.immediateStopped, undefined, name);
  assert.equal(event.pageHandled, true, name);
}

test("the page-world option-click check matches the isolated one", () => {
  const listeners = [];
  const img = picture("Grail", "https://upload.wikimedia.org/grail.jpg");
  const page = {
    window: { innerWidth: 1200, innerHeight: 800, addEventListener: (type, fn) => listeners.push({ type, fn }) },
    document: { addEventListener() {}, elementsFromPoint() { return []; }, querySelectorAll() { return []; } },
  };
  vm.runInNewContext(altStop, page);
  const isolated = {};
  vm.runInNewContext(imageHit, isolated);
  const events = [
    { altKey: true, button: 0 },
    { altKey: false, button: 0 },
    { altKey: false, altState: true, button: 0 },
    { altKey: true, metaKey: true, button: 0 },
    { altKey: true, ctrlKey: true, button: 0 },
    { altKey: true, shiftKey: true, button: 0 },
    { altKey: true, button: 2 },
  ];
  for (const fields of events) {
    const event = {
      type: "click", metaKey: false, ctrlKey: false, shiftKey: false, clientX: 80, clientY: 120, target: img,
      ...fields,
      getModifierState: () => !!fields.altState,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() {},
    };
    for (const l of listeners) if (l.type === "click") l.fn(event);
    assert.equal(!!event.defaultPrevented, isolated.altClick(fields, false), JSON.stringify(fields));
  }
});

test("altStop.js leaves no globals in the page world", () => {
  const page = {
    window: { addEventListener() {} },
    document: { addEventListener() {}, elementsFromPoint() { return []; }, querySelectorAll() { return []; } },
  };
  const before = new Set(Object.keys(page));
  vm.runInNewContext(altStop, page);
  assert.deepEqual(Object.keys(page).filter((k) => !before.has(k)), []);
  for (const name of ["altClick", "insideLink", "contentImage", "imageAt", "saveGesture", "onOptionClick"]) {
    assert.equal(name in page, false, name);
  }
});

test("option-click on a picture saves and does not reach the page, on every site", () => {
  for (const [name, site] of Object.entries(sites)) {
    const { messages, fire } = harness(site);
    const down = fire("pointerdown", 80, 120, site.picture);
    const mouse = fire("mousedown", 80, 120, site.picture);
    assertPassive(down, name + " pointerdown");
    assertPassive(mouse, name + " mousedown");
    assert.deepEqual(messages, [], name);
    const click = fire("click", 80, 120, site.picture);
    assert.equal(messages.length, 1, name);
    assert.equal(messages[0].type, "save-image", name);
    assert.equal(messages[0].srcUrl, site.picture.currentSrc, name);
    assert.equal(click.defaultPrevented, true, name);
    assert.equal(click.propagationStopped, true, name);
    assert.equal(click.pageHandled, undefined, name);
    const again = fire("click", 80, 120, site.picture);
    assert.equal(messages.length, 1, name);
    assert.equal(again.defaultPrevented, true, name);
    assert.equal(again.pageHandled, undefined, name);
  }
});

test("option-click away from a picture is left to the page, on every site", () => {
  for (const [name, site] of Object.entries(sites)) {
    const { messages, fire } = harness(site);
    for (const type of ["pointerdown", "mousedown", "click"]) {
      const event = fire(type, site.otherAt.x, site.otherAt.y, site.other);
      assertPassive(event, name + " " + type);
    }
    assert.deepEqual(messages, [], name);
    const plain = fire("click", 80, 120, site.picture, { altKey: false });
    assertPassive(plain, name + " plain click");
    assert.deepEqual(messages, [], name);
  }
});

test("option-click on a picture inside a link saves it and stops the link download", () => {
  const link = element("A", { left: 40, top: 80, right: 360, bottom: 280, width: 320, height: 200 });
  const linked = element("IMG", { left: 40, top: 80, right: 360, bottom: 280, width: 320, height: 200 }, {
    alt: "Lamp",
    src: "https://i.pinimg.com/736x/lamp.jpg",
    parent: link,
  });
  link.querySelector = () => linked;
  const { messages, fire } = harness(sites.pin, [linked, link]);
  // Pinterest-style: the click lands on the image, or on the link drawn over it.
  for (const target of [linked, link]) {
    const down = fire("pointerdown", 80, 120, target);
    assertPassive(down, "pointerdown");
    const click = fire("click", 80, 120, target);
    assert.equal(click.defaultPrevented, true, "Chrome's Option-click download is cancelled");
    assert.equal(click.propagationStopped, true);
    assert.equal(click.pageHandled, undefined);
  }
  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, "save-image");
  assert.equal(messages[0].srcUrl, "https://i.pinimg.com/736x/lamp.jpg");
  assert.equal(messages[0].title, "Lamp");
});

test("option-click on a plain link or a page-sized image is not a save gesture", () => {
  const hero = element("IMG", { left: 0, top: 0, right: 1200, bottom: 800, width: 1200, height: 800 }, {
    alt: "Hero",
    src: "https://cdn.test/hero.jpg",
  });
  const textLink = element("A", { left: 400, top: 40, right: 520, bottom: 58, width: 120, height: 18 });
  const { messages, fire } = harness(sites.pin, [textLink, hero]);
  const onLink = fire("click", 420, 48, textLink);
  const onHero = fire("click", 1100, 700, hero);
  assertPassive(onLink, "plain link keeps Chrome's Option-click download");
  assertPassive(onHero, "page-sized image");
  assert.deepEqual(messages, []);
});
