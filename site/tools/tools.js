// Renders stills of the wall for og.png and the no-JavaScript fallback. Not deployed (.vercelignore).
// ?theme=dark|light&index=<painting>
(function () {
  var q = new URLSearchParams(location.search), c = document.querySelector("canvas[data-wall]");
  c.setAttribute("data-theme", q.get("theme") || "dark");
  c.setAttribute("data-index", q.get("index") || "0");
  c.setAttribute("data-still", "");
  if (q.get("theme") === "light") document.documentElement.classList.add("light");
})();
