// The Web Store zip has to be built from this tree, not from an older unpacked copy.
import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const chrome = new URL("../chrome/", import.meta.url).pathname;

test("the packaged zip contains the 0.2.9 option-click fix", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "grails-zip-"));
  const zip = path.join(dir, "save-to-grails-0.2.9.zip");
  execFileSync("zip", ["-qr", zip, ".", "-x", "README.md"], { cwd: chrome });
  const out = path.join(dir, "unpacked");
  fs.mkdirSync(out);
  execFileSync("unzip", ["-q", zip, "-d", out]);

  const manifest = JSON.parse(fs.readFileSync(path.join(out, "manifest.json"), "utf8"));
  assert.equal(manifest.version, "0.2.9");
  assert.deepEqual(manifest.host_permissions, ["http://127.0.0.1/*", "http://*/*", "https://*/*"]);
  assert.equal(manifest.content_scripts[0].world, "MAIN");
  assert.deepEqual(manifest.content_scripts[0].js, ["lib/altStop.js"]);
  assert.equal(manifest.content_scripts[0].run_at, "document_start");
  assert.equal(manifest.content_scripts[0].all_frames, true);
  assert.deepEqual(manifest.content_scripts[1].js, ["lib/imageHit.js", "lib/toast.js", "content.js"]);
  assert.equal(manifest.content_scripts[1].world, undefined);

  const altStop = fs.readFileSync(path.join(out, "lib/altStop.js"), "utf8");
  const guardAt = altStop.indexOf("if (!saveGesture(e)) return;");
  const stopAt = altStop.indexOf("e.preventDefault();");
  assert.ok(guardAt !== -1 && stopAt !== -1 && guardAt < stopAt);
  assert.match(altStop, /e\.preventDefault\(\);\s*e\.stopPropagation\(\);/);
  assert.doesNotMatch(altStop, /stopImmediatePropagation/);
  assert.match(altStop, /^\(\(\) => \{$/m);
  assert.match(altStop, /^\}\)\(\);\s*$/m);
  assert.doesNotMatch(altStop, /insideLink/);

  const content = fs.readFileSync(path.join(out, "content.js"), "utf8");
  assert.match(content, /let lastSave = -Infinity;/);
  assert.match(content, /if \(!e \|\| e\.type !== "click"\) return;/);
  assert.match(content, /showGrailsToast\(document,/);
  assert.doesNotMatch(content, /optionDown/);

  const toast = fs.readFileSync(path.join(out, "lib/toast.js"), "utf8");
  assert.match(toast, /attachShadow\(\{ mode: "closed" \}\)/);
  assert.match(toast, /function showGrailsToast/);
  fs.rmSync(dir, { recursive: true, force: true });
});
