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
    enhanceReplyAttachments();
  });

  // Progressive enhancement for the reply form's file input: hide the raw
  // control and swap in a quiet paperclip plus file chips, matching the
  // visitor widget. Without JS the native input stays and still works.
  function enhanceReplyAttachments() {
    var form = document.querySelector("form.reply");
    if (!form) return;
    var input = form.querySelector("input[type=file]");
    if (!input) return;

    input.hidden = true;
    var canEdit = typeof DataTransfer !== "undefined"; // per-file removal needs it

    var button = document.createElement("button");
    button.type = "button";
    button.className = "attach";
    var label = input.getAttribute("aria-label") || "Attach files";
    button.setAttribute("aria-label", label);
    button.title = label;
    // Paperclip (Heroicons, MIT) — same icon as the widget.
    button.innerHTML =
      '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
      '<path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" ' +
      'stroke-linejoin="round" d="M18.4 8.6 9.9 17a3.5 3.5 0 0 1-5-5l8.5-8.4a2.3 2.3 0 0 1 ' +
      '3.3 3.3l-8.5 8.4a1.1 1.1 0 0 1-1.6-1.6l7.8-7.8"/></svg>';
    button.addEventListener("click", function () { input.click(); });
    // The paperclip lives in the toolbar (left of send); chips sit at the top
    // of the box — so it reads as one composer, like the visitor widget.
    (form.querySelector(".reply-tools") || form).appendChild(button);

    var chips = document.createElement("div");
    chips.className = "chips";
    chips.hidden = true;
    form.insertBefore(chips, form.firstChild);

    input.addEventListener("change", render);

    function render() {
      var files = Array.prototype.slice.call(input.files);
      chips.textContent = "";
      chips.hidden = files.length === 0;
      files.forEach(function (file, index) {
        var chip = document.createElement("span");
        chip.className = "chip";
        var name = document.createElement("span");
        name.className = "chip-name";
        name.textContent = file.name;
        chip.appendChild(name);
        if (canEdit) {
          var remove = document.createElement("button");
          remove.type = "button";
          remove.className = "chip-x";
          remove.setAttribute("aria-label", "Remove file");
          remove.innerHTML = "&times;";
          remove.addEventListener("click", function () { removeAt(index); });
          chip.appendChild(remove);
        }
        chips.appendChild(chip);
      });
    }

    function removeAt(index) {
      var kept = new DataTransfer();
      Array.prototype.slice.call(input.files).forEach(function (file, i) {
        if (i !== index) kept.items.add(file);
      });
      input.files = kept.files;
      render();
    }
  }

  // The conversation list keeps itself fresh: when the server's token moves
  // (new message, new thread, resolve/reopen), just reload — unless the
  // agent is mid-search, whose typing must never be eaten.
  function watchIndex() {
    var index = document.getElementById("lvc-index");
    if (!index) return;

    var token = index.getAttribute("data-token");
    var url = index.getAttribute("data-poll-url");
    var searchBox = document.querySelector(".filters input[type=search]");

    function check() {
      if (document.hidden) return;
      // Never reload out from under an agent who is typing a search.
      if (searchBox && searchBox.value !== searchBox.defaultValue) return;
      if (searchBox && document.activeElement === searchBox) return;
      fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(function (response) { return response.ok ? response.json() : null; })
        .then(function (data) {
          if (data && data.token !== token) window.location.reload();
        })
        .catch(function () { /* transient network error — next tick retries */ });
    }

    setInterval(check, POLL_MS);
    // Action Cable (opt-in): a nudge runs the check at once, so the list
    // refreshes the instant something changes. Polling stays the fallback.
    openCable(index, check);
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
      // Grow the box with the reply, up to the CSS max-height — matching the
      // widget composer instead of a fixed two-row field.
      var autogrow = function () {
        replyBox.style.height = "auto";
        replyBox.style.height = Math.min(replyBox.scrollHeight, 160) + "px";
      };
      replyBox.addEventListener("input", autogrow);
      autogrow();
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
      if (message.body) bubble.appendChild(document.createTextNode(message.body));
      appendAttachments(bubble, message.attachments);
      thread.appendChild(bubble);
    }

    // Mirrors the server-rendered thread: images inline, other files as links,
    // all pointing at the engine's gated attachment route.
    function appendAttachments(bubble, attachments) {
      if (!attachments || !attachments.length) return;
      var wrap = document.createElement("div");
      wrap.className = "atts";
      attachments.forEach(function (att) {
        var link = document.createElement("a");
        link.href = att.url;
        link.target = "_blank";
        link.rel = "noopener";
        if (att.image) {
          link.className = "att-img";
          var img = document.createElement("img");
          img.src = att.url;
          img.alt = att.name;
          img.loading = "lazy";
          link.appendChild(img);
        } else {
          link.className = "att-file";
          link.textContent = att.name;
        }
        wrap.appendChild(link);
      });
      bubble.appendChild(wrap);
    }

    function refresh() {
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
    }

    setInterval(refresh, POLL_MS);
    // Action Cable (opt-in): a nudge fetches new messages at once instead of
    // waiting for the next tick. Polling stays the fallback.
    openCable(thread, refresh);
  }

  // A tiny Action Cable client over the native WebSocket protocol — no
  // @rails/actioncable dependency, no build step. It opens only when the
  // element carries a signed stream (push turned on); otherwise polling alone
  // carries the page. The broadcast is a nudge with no payload: on any data
  // message we just run onNudge, which refetches through the gated endpoint.
  function openCable(el, onNudge) {
    var path = el.getAttribute("data-cable-url");
    var stream = el.getAttribute("data-cable-stream");
    if (!path || !stream || !window.WebSocket) return;

    var identifier = JSON.stringify({ channel: "Livechat::StreamChannel", signed_stream: stream });
    var socket;
    try {
      var proto = location.protocol === "https:" ? "wss://" : "ws://";
      socket = new WebSocket(proto + location.host + path, ["actioncable-v1-json"]);
    } catch (e) {
      return; // polling still covers the page
    }
    socket.onmessage = function (event) {
      var data;
      try { data = JSON.parse(event.data); } catch (e) { return; }
      if (data.type === "welcome") {
        socket.send(JSON.stringify({ command: "subscribe", identifier: identifier }));
      } else if (data.message) {
        onNudge();
      }
    };
  }
})();
