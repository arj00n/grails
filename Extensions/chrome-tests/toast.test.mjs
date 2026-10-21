// The saved card is drawn in a closed shadow tree, so a page stylesheet cannot restyle it.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const toast = fs.readFileSync(new URL("../chrome/lib/toast.js", import.meta.url), "utf8");

function element(tag) {
  return {
    tagName: String(tag).toUpperCase(),
    id: "",
    className: "",
    textContent: "",
    style: {},
    children: [],
    attributes: {},
    parent: null,
    shadow: null,
    shadowMode: null,
    setAttribute(name, value) {
      this.attributes[name] = value;
      if (name === "id") this.id = value;
    },
    append(...kids) {
      for (const kid of kids) {
        kid.parent = this;
        this.children.push(kid);
      }
    },
    appendChild(kid) {
      this.append(kid);
      return kid;
    },
    remove() {
      if (!this.parent) return;
      this.parent.children = this.parent.children.filter((kid) => kid !== this);
      this.parent = null;
    },
    attachShadow(init) {
      this.shadowMode = init && init.mode;
      this.shadow = {
        children: [],
        append(...kids) { for (const kid of kids) this.children.push(kid); },
      };
      return this.shadow;
    },
  };
}

function makeDocument() {
  const doc = {
    documentElement: element("html"),
    createElement: element,
    getElementById(id) {
      const walk = (node) => {
        if (!node) return null;
        if (node.id === id) return node;
        for (const kid of node.children || []) {
          const found = walk(kid);
          if (found) return found;
        }
        return null;
      };
      return walk(doc.documentElement);
    },
  };
  return doc;
}

function load() {
  const timers = [];
  const document = makeDocument();
  const sandbox = {
    document,
    setTimeout(fn) {
      const timer = { fn };
      timers.push(timer);
      return timer;
    },
    clearTimeout() {},
  };
  vm.runInNewContext(toast, sandbox);
  return { document, timers, showGrailsToast: sandbox.showGrailsToast };
}

test("a success toast is Geist, greys, and closed shadow, then dismisses itself", () => {
  const { document, timers, showGrailsToast } = load();
  const shown = showGrailsToast(document, { ok: true, text: "Saved to Grails", dismissAfter: 2600 });
  const css = shown.shadow.children[0].textContent;

  assert.equal(shown.host.shadowMode, "closed");
  assert.equal(shown.host.attributes["data-grails-toast"], "ok");
  assert.equal(shown.host.children.length, 0);
  assert.equal(shown.card.className, "toast");
  assert.equal(shown.label.textContent, "Saved to Grails");
  assert.equal(shown.label.parent, shown.card);
  assert.ok(shown.shadow.children.includes(shown.card));
  assert.ok(!shown.host.children.includes(shown.label));
  assert.match(css, /font: 13px\/1\.5 Geist, "Geist"/);
  assert.match(css, /"Geist Mono"/);
  assert.match(css, /--text: #1A1A1A/);
  assert.match(css, /--text: #F3F4F6/);
  assert.match(css, /--status-ok: #2DA44E/);
  assert.match(css, /--status-ok: #3FB950/);
  assert.match(css, /prefers-color-scheme: dark/);
  assert.equal(document.getElementById("__grails_toast"), shown.host);

  assert.equal(timers.length, 1);
  timers[0].fn();
  assert.equal(document.getElementById("__grails_toast"), null);
});

test("an error toast uses the error variant and is not restyled by the page", () => {
  const { document, showGrailsToast } = load();
  const shown = showGrailsToast(document, { ok: false, text: "Couldn't reach Grails" });
  const css = shown.shadow.children[0].textContent;

  assert.equal(shown.host.shadowMode, "closed");
  assert.equal(shown.host.attributes["data-grails-toast"], "error");
  assert.equal(shown.card.className, "toast error");
  assert.equal(shown.label.textContent, "Couldn't reach Grails");
  assert.equal(shown.host.children.length, 0);
  assert.match(css, /\.toast\.error \.mark/);
  assert.match(css, /--status-error: #CF222E/);
  assert.match(css, /--status-error: #F85149/);
  assert.match(css, /:host \{ all: initial; \}/);
});
