// Page world, document_start. This listener is passive for every event that is not the
// extension's save gesture. A normal Option-click keeps the browser's own behaviour
// (download a link, open a picture). preventDefault and stopPropagation run only for a
// click on a content-sized picture, including one inside a link (a Pinterest pin, an
// image grid): that stops Chrome's own Option-click download of the link.
// Chrome runs a content-script URL once, so this file does not load imageHit.js.
// Wrapped so nothing here becomes a page global.
(() => {
  function altClick(e, optionHeld) {
    if (!e || e.metaKey || e.ctrlKey || e.shiftKey) return false;
    if (e.button != null && e.button !== 0) return false;
    return !!(e.altKey || e.altState || optionHeld);
  }

  function contentImage(img, x, y) {
    if (!img || img.tagName !== "IMG") return false;
    const r = img.getBoundingClientRect();
    if (r.width < 48 || r.height < 48) return false;
    if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;
    const view = Math.max(window.innerWidth * window.innerHeight, 1);
    if (r.width * r.height > view * 0.85) return false;
    return true;
  }

  // The picture under the cursor, not an image somewhere else on the page and not the page's own background.
  function imageAt(x, y, target) {
    if (contentImage(target, x, y)) return target;
    const stack = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
    for (const el of stack) {
      if (el === document.body || el === document.documentElement) break;
      if (contentImage(el, x, y)) return el;
      const img = el.querySelector ? el.querySelector("img") : null;
      if (contentImage(img, x, y)) return img;
    }
    return null;
  }

  function saveGesture(e) {
    if (!e || e.type !== "click") return false;
    if (!altClick({
      altKey: e.altKey,
      metaKey: e.metaKey,
      ctrlKey: e.ctrlKey,
      shiftKey: e.shiftKey,
      button: e.button,
      altState: e.getModifierState ? e.getModifierState("Alt") : false,
    }, false)) return false;
    return !!imageAt(e.clientX, e.clientY, e.target);
  }

  function onOptionClick(e) {
    if (!saveGesture(e)) return;
    e.preventDefault();
    e.stopPropagation();
  }

  window.addEventListener("pointerdown", onOptionClick, true);
  window.addEventListener("mousedown", onOptionClick, true);
  window.addEventListener("click", onOptionClick, true);
})();
