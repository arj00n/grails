// The on-page "Saved" card. Shadow DOM so the page's CSS cannot hide or restyle it.
// GrailsDesign greys. SF Pro (the system font) for the message and the name, nothing bundled. Light and dark follow the system.

function grailsToastCSS() {
  return `
    :host { all: initial; }
    .toast {
      position: fixed; z-index: 2147483647; right: 16px; bottom: 16px;
      display: flex; align-items: center; gap: 10px;
      max-width: 320px; padding: 12px 14px; border-radius: 12px;
      border: 1px solid var(--field-border);
      background: var(--background); color: var(--text);
      box-shadow: 0 1px 2px rgba(0,0,0,.04), 0 12px 40px rgba(0,0,0,.10);
      color-scheme: light dark;
      font: 13px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      --background: #FFFFFF; --text: #1A1A1A; --secondary: #6B6B68;
      --field-border: #DCDCD8; --status-ok: #2DA44E; --status-error: #CF222E;
    }
    @media (prefers-color-scheme: dark) {
      .toast {
        --background: #1C1D20; --text: #F3F4F6; --secondary: #9A9CA2;
        --field-border: #323338; --status-ok: #3FB950; --status-error: #F85149;
        box-shadow: 0 0 0 0.5px rgba(255,255,255,.06), 0 16px 48px rgba(0,0,0,.5);
      }
    }
    .mark { width: 6px; height: 6px; border-radius: 50%; background: var(--status-ok); flex: none; }
    .toast.error .mark { background: var(--status-error); }
    .name { font: 400 12px/1.2 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; color: var(--secondary); }
    .label { color: var(--text); }
  `;
}

/** Shows the card and removes it after `dismissAfter` ms. The message lives in the shadow tree. */
function showGrailsToast(doc, { ok = true, text = "", dismissAfter = 2600 } = {}) {
  const rootDoc = doc || document;
  rootDoc.getElementById("__grails_toast")?.remove();
  const host = rootDoc.createElement("div");
  host.id = "__grails_toast";
  host.setAttribute("data-grails-toast", ok ? "ok" : "error");
  host.style.cssText = "all: initial; position: fixed; z-index: 2147483647; right: 0; bottom: 0; pointer-events: none;";
  const shadow = host.attachShadow({ mode: "closed" });
  const style = rootDoc.createElement("style");
  style.textContent = grailsToastCSS();
  const card = rootDoc.createElement("div");
  card.className = ok ? "toast" : "toast error";
  const mark = rootDoc.createElement("span");
  mark.className = "mark";
  const name = rootDoc.createElement("span");
  name.className = "name";
  name.textContent = "GRAILS";
  const label = rootDoc.createElement("span");
  label.className = "label";
  label.textContent = text;
  card.append(mark, name, label);
  shadow.append(style, card);
  (rootDoc.documentElement || rootDoc.body).appendChild(host);
  const timer = setTimeout(() => host.remove(), dismissAfter);
  return { host, shadow, card, label, timer };
}
