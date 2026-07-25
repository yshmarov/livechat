/*
 * livechat dashboard — the little JavaScript the inbox needs, served as a
 * same-origin script so it works under strict CSPs (no inline handlers).
 *
 * On a conversation page it polls for new messages every few seconds. If the
 * reply box is empty the page just reloads to show them; if the agent is
 * mid-sentence it shows a "New messages" link instead — a reload must never
 * eat a half-written reply. Cmd/Ctrl+Enter sends.
 */
(function () {
  "use strict";

  var POLL_MS = 5000;

  function ready(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  ready(function () {
    watchIndex();
    watchThread();
  });

  // The conversation list keeps itself fresh: when the server's token moves
  // (new message, new thread, resolve/reopen), just reload — unless the
  // agent is mid-search, whose typing must never be eaten.
  function watchIndex() {
    var index = document.getElementById("lvc-index");
    if (!index) return;

    var token = index.getAttribute("data-token");
    var url = index.getAttribute("data-poll-url");
    var searchBox = document.querySelector(".filters input[type=search]");

    setInterval(function () {
      if (document.hidden) return;
      if (searchBox && searchBox.value !== searchBox.defaultValue) return;
      if (searchBox && document.activeElement === searchBox) return;
      fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(function (response) { return response.ok ? response.json() : null; })
        .then(function (data) {
          if (data && data.token !== token) window.location.reload();
        })
        .catch(function () { /* transient network error — next tick retries */ });
    }, POLL_MS);
  }

  function watchThread() {
    var thread = document.getElementById("thread");
    if (!thread) return;

    thread.scrollTop = thread.scrollHeight;

    var replyBox = document.querySelector(".reply textarea");
    var latest = parseInt(thread.getAttribute("data-latest"), 10) || 0;
    var lastAuthorKey = thread.getAttribute("data-last-author") || null;
    var url = thread.getAttribute("data-poll-url");

    if (replyBox) {
      replyBox.addEventListener("keydown", function (event) {
        if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          replyBox.form.requestSubmit();
        }
      });
    }

    // New messages are appended in place — never a reload — so a half-written
    // reply is never lost and scroll position is kept unless you're at the
    // bottom. Author headers group exactly like the server-rendered thread.
    function append(message) {
      if (message.id <= latest) return;
      latest = message.id;

      if (message.author === "system") {
        var line = document.createElement("p");
        line.className = "system";
        line.id = "message-" + message.id;
        line.textContent = message.text + " · " + message.at;
        thread.appendChild(line);
        lastAuthorKey = null;
        return;
      }

      var key = message.author + ":" + (message.name || "");
      if (key !== lastAuthorKey) {
        var who = document.createElement("p");
        who.className = "who " + message.author;
        who.textContent = message.name + " · " + message.at;
        thread.appendChild(who);
        lastAuthorKey = key;
      }
      var bubble = document.createElement("div");
      bubble.className = "msg " + message.author;
      bubble.id = "message-" + message.id;
      bubble.textContent = message.body;
      thread.appendChild(bubble);
    }

    setInterval(function () {
      if (document.hidden) return;
      // Only auto-scroll if the agent is already reading the latest — don't
      // yank them down while they've scrolled up through history.
      var atBottom = thread.scrollHeight - thread.scrollTop - thread.clientHeight < 60;
      fetch(url + "?after=" + latest, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(function (response) { return response.ok ? response.json() : null; })
        .then(function (data) {
          if (!data || !data.messages || !data.messages.length) return;
          data.messages.forEach(append);
          if (atBottom) thread.scrollTop = thread.scrollHeight;
        })
        .catch(function () { /* transient network error — next tick retries */ });
    }, POLL_MS);
  }
})();
