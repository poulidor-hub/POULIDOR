// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

(function () {
  "use strict";
  // Source de vérité : fichier `VERSION` à la racine du parc POULIDOR.
  // À resynchroniser à chaque release (cf. skill release-on-main).
  var PARC_VERSION = "0.82.30";

  function addCopyButtons() {
    var blocks = document.querySelectorAll(".code");
    blocks.forEach(function (block) {
      var pre = block.querySelector("pre");
      if (!pre) return;
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy";
      btn.textContent = "Copier";
      btn.addEventListener("click", function () {
        var text = pre.innerText;
        var done = function () {
          btn.textContent = "Copié !";
          setTimeout(function () { btn.textContent = "Copier"; }, 1500);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, fallback);
        } else {
          fallback();
        }
        function fallback() {
          var ta = document.createElement("textarea");
          ta.value = text;
          document.body.appendChild(ta);
          ta.select();
          try { document.execCommand("copy"); } catch (e) {}
          document.body.removeChild(ta);
          done();
        }
      });
      block.appendChild(btn);
    });
  }

  function highlightNav() {
    var here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll(".topnav a").forEach(function (a) {
      var target = a.getAttribute("href");
      if (target === here) a.classList.add("active");
    });
  }

  function fillVersion() {
    document.querySelectorAll("[data-parc-version]").forEach(function (el) {
      el.textContent = PARC_VERSION;
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    addCopyButtons();
    highlightNav();
    fillVersion();
  });
})();
