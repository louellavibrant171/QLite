// Language switching for the QLite site.
//
// Every translatable node carries data-en and data-zh attributes; swapping languages rewrites
// their text in place. The choice is remembered, and defaults to the browser's language.

(function () {
  "use strict";

  var STORAGE_KEY = "qlite-site-lang";
  var toggle = document.getElementById("lang-toggle");

  function preferredLanguage() {
    var stored = null;
    try {
      stored = localStorage.getItem(STORAGE_KEY);
    } catch (error) {
      // Private browsing: fall through to the browser language.
    }
    if (stored === "en" || stored === "zh") {
      return stored;
    }
    var languages = navigator.languages || [navigator.language || "en"];
    return String(languages[0]).toLowerCase().indexOf("zh") === 0 ? "zh" : "en";
  }

  function apply(lang) {
    var attribute = lang === "zh" ? "data-zh" : "data-en";

    document.querySelectorAll("[data-en][data-zh]").forEach(function (node) {
      var value = node.getAttribute(attribute);
      if (value === null) {
        return;
      }
      // <meta> carries its text in an attribute rather than as a child node.
      if (node.tagName === "META") {
        node.setAttribute("content", value);
      } else {
        node.textContent = value;
      }
    });

    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.title = lang === "zh"
      ? "QLite — macOS 原生 SQLite 数据库查看器"
      : "QLite — a native SQLite browser for macOS";

    // The button offers the other language, which is what the user is about to get.
    toggle.textContent = lang === "zh" ? "EN" : "中文";
    toggle.setAttribute("aria-label", lang === "zh" ? "Switch to English" : "切换到中文");

    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch (error) {
      // Not being able to remember the choice is not worth failing over.
    }
  }

  var current = preferredLanguage();
  apply(current);

  toggle.addEventListener("click", function () {
    current = current === "zh" ? "en" : "zh";
    apply(current);
  });
})();
