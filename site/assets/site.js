/* Copy buttons. Everything else on the page works without JavaScript. */
(function () {
  "use strict";
  if (!navigator.clipboard || !window.isSecureContext) return;
  var buttons = document.querySelectorAll("[data-copy]");
  Array.prototype.forEach.call(buttons, function (button) {
    var target = document.getElementById(button.getAttribute("data-copy"));
    if (!target) return;
    var label = button.textContent, timer = 0;
    button.hidden = false;
    button.addEventListener("click", function () {
      navigator.clipboard.writeText(target.textContent.trim()).then(function () {
        button.textContent = "Copied";
        clearTimeout(timer);
        timer = setTimeout(function () { button.textContent = label; }, 1600);
      });
    });
  });
})();
