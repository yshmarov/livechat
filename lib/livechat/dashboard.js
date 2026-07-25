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
    var thread = document.getElementById("thread");
    if (!thread) return;

    thread.scrollTop = thread.scrollHeight;

    var replyBox = document.querySelector(".reply textarea");
    var banner = document.getElementById("new-messages");
    var latest = parseInt(thread.getAttribute("data-latest"), 10) || 0;
    var url = thread.getAttribute("data-poll-url");

    if (replyBox) {
      replyBox.addEventListener("keydown", function (event) {
        if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          replyBox.form.requestSubmit();
        }
      });
    }

    setInterval(function () {
      if (document.hidden) return;
      fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(function (response) { return response.ok ? response.json() : null; })
        .then(function (data) {
          if (!data || data.latest <= latest) return;
          if (!replyBox || replyBox.value.trim() === "") {
            window.location.reload();
          } else if (banner) {
            banner.hidden = false;
          }
        })
        .catch(function () { /* transient network error — next tick retries */ });
    }, POLL_MS);
  });
})();
