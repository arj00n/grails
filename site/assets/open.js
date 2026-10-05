/* The invite-link page: https://grails.arjoon.xyz/open#lib=…&name=…(&c=|t=|i=)(&v=canvas).
   The link's details sit after the #, so they never reach this server. The page hands them to the app as
   grails://open?<the same query>, untouched (GrailsLink in GrailsKit reads it), and offers the download. */
(function () {
  "use strict";
  var KEYS = ["lib", "name", "c", "t", "i", "v"];
  var pairs = location.hash.replace(/^#/, "").split("&").filter(function (p) {
    var eq = p.indexOf("=");
    return eq > 0 && KEYS.indexOf(p.slice(0, eq)) >= 0;
  });
  function get(key) {
    for (var n = 0; n < pairs.length; n++) {
      var eq = pairs[n].indexOf("=");
      if (pairs[n].slice(0, eq) === key) {
        try { return decodeURIComponent(pairs[n].slice(eq + 1)); } catch (e) { return pairs[n].slice(eq + 1); }
      }
    }
    return "";
  }

  var what = document.getElementById("what");
  var open = document.getElementById("open");
  var fallback = document.getElementById("fallback");
  var lib = get("lib"), name = get("name").slice(0, 80);

  // another link opened in this same tab only changes the #: start over
  window.addEventListener("hashchange", function () { location.reload(); });

  if (!lib) {
    what.textContent = "This link is incomplete";
    fallback.hidden = true;
    document.title = "Incomplete link · Grails";
    return;
  }

  var app = "grails://open?" + pairs.join("&");
  open.href = app;
  open.hidden = false;

  var kind = get("c") ? "a collection in " : get("t") ? "a tag in " : get("i") ? "a picture in " : "";
  what.textContent = "";
  what.appendChild(document.createTextNode("A link to " + kind));
  if (name) {
    var b = document.createElement("b");
    b.textContent = name;
    what.appendChild(b);
    document.title = "Open " + name + " in Grails";
  } else {
    what.appendChild(document.createTextNode("a Grails library"));
  }

  // Try the app once. A browser can't tell whether it opened, so the download line follows either way.
  setTimeout(function () { location.href = app; }, 150);
  setTimeout(function () { fallback.classList.add("shown"); }, 1400);
})();
