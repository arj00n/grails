import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const script = new URL("../../Scripts/embed-safari-extension.sh", import.meta.url).pathname;

function layout() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "grails-embed-"));
  const products = path.join(root, "Products");
  const built = path.join(products, "Grails.app");
  const src = path.join(products, "GrailsSafari.appex");
  fs.mkdirSync(path.join(src, "Contents"), { recursive: true });
  fs.writeFileSync(path.join(src, "Contents", "Info.plist"), "appex");
  const dest = path.join(built, "Contents", "PlugIns", "GrailsSafari.appex");
  return { root, products, built, src, dest };
}

function plant(dest) {
  fs.mkdirSync(path.join(dest, "Contents"), { recursive: true });
  fs.writeFileSync(path.join(dest, "Contents", "Info.plist"), "stale");
}

function run(env) {
  execFileSync(script, { env: { ...process.env, ...env }, stdio: "pipe" });
}

test("anything other than YES removes the appex and does not copy it", () => {
  for (const flag of ["NO", "yes", "true", "", undefined]) {
    const { root, products, built, src, dest } = layout();
    try {
      plant(dest);
      const env = {
        ...process.env,
        TARGET_BUILD_DIR: products,
        WRAPPER_NAME: "Grails.app",
        BUILT_PRODUCTS_DIR: products,
      };
      delete env.GRAILS_SAFARI_EXTENSION;
      if (flag !== undefined) env.GRAILS_SAFARI_EXTENSION = flag;
      execFileSync(script, { env, stdio: "pipe" });
      assert.equal(fs.existsSync(dest), false, `flag ${String(flag)}`);
      assert.equal(fs.existsSync(src), true);
      assert.equal(fs.existsSync(built), true);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }
});

test("YES copies the built appex into PlugIns", () => {
  const { root, products, src, dest } = layout();
  try {
    run({
      TARGET_BUILD_DIR: products,
      WRAPPER_NAME: "Grails.app",
      BUILT_PRODUCTS_DIR: products,
      GRAILS_SAFARI_EXTENSION: "YES",
    });
    assert.equal(fs.readFileSync(path.join(dest, "Contents", "Info.plist"), "utf8"), "appex");
    assert.equal(fs.existsSync(src), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("YES fails when the built appex is missing and leaves a previous copy", () => {
  const { root, products, src, dest } = layout();
  try {
    plant(dest);
    fs.rmSync(src, { recursive: true, force: true });
    assert.throws(() =>
      run({
        TARGET_BUILD_DIR: products,
        WRAPPER_NAME: "Grails.app",
        BUILT_PRODUCTS_DIR: products,
        GRAILS_SAFARI_EXTENSION: "YES",
      })
    );
    assert.equal(fs.readFileSync(path.join(dest, "Contents", "Info.plist"), "utf8"), "stale");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
