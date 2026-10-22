import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const chrome = new URL("../chrome/", import.meta.url).pathname;
const script = new URL("../../Scripts/copy-safari-extension-resources.sh", import.meta.url).pathname;

test("the copy script puts the chrome tree at the resources root", () => {
  const dest = fs.mkdtempSync(path.join(os.tmpdir(), "grails-safari-"));
  try {
    execFileSync(script, {
      env: { ...process.env, SRC: chrome, DEST: dest },
      stdio: "pipe",
    });
    for (const rel of ["manifest.json", "background.js", "lib/client.js", "icons/128.png", "fonts/Geist-Regular.ttf"]) {
      assert.equal(fs.existsSync(path.join(dest, rel)), true, rel);
    }
    assert.equal(fs.existsSync(path.join(dest, "chrome", "manifest.json")), false);
    assert.equal(fs.existsSync(path.join(dest, "client.js")), false);
    assert.equal(fs.existsSync(path.join(dest, "README.md")), false);
    assert.deepEqual(fs.readFileSync(path.join(dest, "manifest.json")), fs.readFileSync(path.join(chrome, "manifest.json")));
  } finally {
    fs.rmSync(dest, { recursive: true, force: true });
  }
});

test("the copy script accepts an appex Resources destination", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "grails-safari-appex-"));
  const dest = path.join(dir, "GrailsSafari.appex", "Contents", "Resources");
  try {
    const env = {
      ...process.env,
      SRC: chrome,
      TARGET_BUILD_DIR: dir,
      UNLOCALIZED_RESOURCES_FOLDER_PATH: "GrailsSafari.appex/Contents/Resources",
    };
    delete env.DEST;
    execFileSync(script, { env, stdio: "pipe" });
    assert.equal(fs.existsSync(path.join(dest, "manifest.json")), true);
    assert.equal(fs.existsSync(path.join(dest, "lib", "client.js")), true);
    assert.equal(fs.existsSync(path.join(dest, "client.js")), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("the copy script refuses an Xcode destination outside the appex", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "grails-safari-bad-"));
  try {
    const env = {
      ...process.env,
      SRC: chrome,
      TARGET_BUILD_DIR: dir,
      UNLOCALIZED_RESOURCES_FOLDER_PATH: "Resources",
    };
    delete env.DEST;
    assert.throws(() => execFileSync(script, { env, stdio: "pipe" }));
    assert.equal(fs.existsSync(path.join(dir, "Resources", "manifest.json")), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
