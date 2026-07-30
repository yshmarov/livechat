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
    var labels = {
      recordAudio: form.dataset.recordAudio || "Record audio",
      stopRecording: form.dataset.stopRecording || "Stop recording",
      cancelRecording: form.dataset.cancelRecording || "Cancel recording",
      recording: form.dataset.recording || "Recording %{time}",
      microphoneUnsupported: form.dataset.microphoneUnsupported || "Audio recording is not supported in this browser.",
      microphoneDenied: form.dataset.microphoneDenied || "Microphone access was blocked. Allow microphone access in your browser and try again.",
      microphoneError: form.dataset.microphoneError || "Could not start audio recording."
    };

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
    var tools = form.querySelector(".reply-tools") || form;
    tools.appendChild(button);

    var recordButton = null;
    if (canEdit) {
      recordButton = document.createElement("button");
      recordButton.type = "button";
      recordButton.className = "attach record";
      recordButton.setAttribute("aria-label", labels.recordAudio);
      recordButton.title = labels.recordAudio;
      recordButton.innerHTML =
        '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
        '<path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
        'stroke-linejoin="round" d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3Z' +
        'M5 11a7 7 0 0 0 14 0M12 18v3M8.5 21h7"/></svg>';
      tools.appendChild(recordButton);
    }

    var chips = document.createElement("div");
    chips.className = "chips";
    chips.hidden = true;
    form.insertBefore(chips, form.firstChild);

    input.addEventListener("change", render);
    if (recordButton) enhanceAudioRecorder();

    function render() {
      var files = Array.prototype.slice.call(input.files);
      chips.textContent = "";
      chips.hidden = files.length === 0;
      files.forEach(function (file, index) {
        var chip = document.createElement("span");
        chip.className = "chip";
        var name = document.createElement("span");
        name.className = "chip-name";
        name.textContent = file.name || "voice-message.webm";
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

    function enhanceAudioRecorder() {
      var recorder = null;
      var stream = null;
      var chunks = [];
      var startedAt = 0;
      var timer = null;
      var cancelled = false;

      var bar = document.createElement("div");
      bar.className = "recording";
      bar.hidden = true;
      var status = document.createElement("span");
      status.className = "recording-status";
      status.setAttribute("aria-live", "polite");
      var dot = document.createElement("span");
      dot.className = "recording-dot";
      var rec = document.createElement("span");
      rec.className = "recording-rec";
      rec.textContent = "REC";
      var time = document.createElement("span");
      status.appendChild(dot);
      status.appendChild(rec);
      status.appendChild(time);
      bar.appendChild(status);
      var actions = document.createElement("div");
      actions.className = "recording-actions";
      var cancel = document.createElement("button");
      cancel.type = "button";
      cancel.setAttribute("aria-label", labels.cancelRecording);
      cancel.title = labels.cancelRecording;
      cancel.innerHTML =
        '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true">' +
        '<path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" ' +
        'd="M6 6l12 12M18 6 6 18"/></svg>';
      var stop = document.createElement("button");
      stop.type = "button";
      stop.className = "stop-recording";
      stop.setAttribute("aria-label", labels.stopRecording);
      stop.title = labels.stopRecording;
      stop.innerHTML =
        '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
        '<rect x="5" y="5" width="14" height="14" rx="2" fill="currentColor"/></svg>';
      actions.appendChild(cancel);
      actions.appendChild(stop);
      bar.appendChild(actions);
      tools.appendChild(bar);
      var sendButton = form.querySelector(".send");

      recordButton.addEventListener("click", start);
      stop.addEventListener("click", function () {
        if (recorder && recorder.state !== "inactive") recorder.stop();
      });
      cancel.addEventListener("click", function () {
        cancelled = true;
        if (recorder && recorder.state !== "inactive") recorder.stop();
      });

      function start() {
        if (recorder) return;
        if (!recordingSupported()) {
          alert(labels.microphoneUnsupported);
          return;
        }

        recordButton.disabled = true;
        navigator.mediaDevices.getUserMedia({ audio: true })
          .then(function (mediaStream) {
            var options = preferredAudioOptions();
            chunks = [];
            cancelled = false;
            stream = mediaStream;
            try {
              recorder = options ? new MediaRecorder(mediaStream, options) : new MediaRecorder(mediaStream);
            } catch (e) {
              stopTracks();
              throw e;
            }
            recorder.addEventListener("dataavailable", function (event) {
              if (event.data && event.data.size) chunks.push(event.data);
            });
            recorder.addEventListener("stop", finish);
            recorder.start();
            startedAt = Date.now();
            recordButton.classList.add("recording-on");
            form.classList.add("is-recording");
            if (sendButton) sendButton.disabled = true;
            bar.hidden = false;
            tick();
            timer = setInterval(tick, 500);
          })
          .catch(function (error) {
            recordButton.disabled = false;
            var denied = error && (error.name === "NotAllowedError" || error.name === "SecurityError");
            alert(denied ? labels.microphoneDenied : labels.microphoneError);
          });
      }

      function finish() {
        var mimeType = (recorder && recorder.mimeType) || "audio/webm";
        stopTracks();
        clearInterval(timer);
        timer = null;
        bar.hidden = true;
        recordButton.disabled = false;
        recordButton.classList.remove("recording-on");
        form.classList.remove("is-recording");
        if (sendButton) sendButton.disabled = false;

        if (!cancelled && chunks.length && typeof DataTransfer !== "undefined") {
          var kept = new DataTransfer();
          Array.prototype.slice.call(input.files).forEach(function (file) { kept.items.add(file); });
          kept.items.add(audioFile(chunks, mimeType));
          input.files = kept.files;
          render();
        }
        recorder = null;
        chunks = [];
      }

      function tick() {
        var elapsed = formatDuration(Date.now() - startedAt);
        time.textContent = elapsed;
        status.setAttribute("aria-label", labels.recording.replace("%{time}", elapsed));
      }

      function stopTracks() {
        if (!stream) return;
        stream.getTracks().forEach(function (track) { track.stop(); });
        stream = null;
      }
    }
  }

  function recordingSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  }

  function preferredAudioOptions() {
    var types = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"];
    if (!window.MediaRecorder || !MediaRecorder.isTypeSupported) return null;
    for (var i = 0; i < types.length; i++) {
      if (MediaRecorder.isTypeSupported(types[i])) return { mimeType: types[i] };
    }
    return null;
  }

  function audioFile(chunks, mimeType) {
    var blob = new Blob(chunks, { type: mimeType });
    var name = "voice-message-" + new Date().toISOString().replace(/[:.]/g, "-") + "." + audioExtension(mimeType);
    try {
      return new File([blob], name, { type: mimeType });
    } catch (e) {
      blob.name = name;
      return blob;
    }
  }

  function audioExtension(mimeType) {
    if (/mp4|mpeg|m4a/.test(mimeType)) return "m4a";
    if (/ogg/.test(mimeType)) return "ogg";
    return "webm";
  }

  function formatDuration(ms) {
    var seconds = Math.max(0, Math.floor(ms / 1000));
    var minutes = Math.floor(seconds / 60);
    seconds = seconds % 60;
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
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
    var replyBox = document.querySelector(".reply textarea");

    function check() {
      if (document.hidden) return;
      // Never reload out from under an agent who is typing a search.
      if (searchBox && searchBox.value !== searchBox.defaultValue) return;
      if (searchBox && document.activeElement === searchBox) return;
      // On the two-column inbox, the selected thread lives beside the list.
      // Let thread polling append messages while a reply draft is active.
      if (replyBox && replyBox.value.trim()) return;
      if (replyBox && document.activeElement === replyBox) return;
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

    // Stick to the bottom until the agent scrolls up. Images (screenshots and
    // attachments) finish loading after DOMContentLoaded and grow the thread,
    // so a single scroll-to-bottom now would land mid-thread once they expand
    // — re-pin as each image loads and once the page has fully loaded.
    var stick = true;
    var keepBottom = function () { if (stick) thread.scrollTop = thread.scrollHeight; };
    thread.addEventListener("scroll", function () {
      stick = thread.scrollHeight - thread.scrollTop - thread.clientHeight < 80;
    });
    keepBottom();
    var images = thread.querySelectorAll("img");
    for (var i = 0; i < images.length; i++) {
      if (!images[i].complete) images[i].addEventListener("load", keepBottom);
    }
    window.addEventListener("load", keepBottom);

    var replyBox = document.querySelector(".reply textarea");
    var latest = parseInt(thread.getAttribute("data-latest"), 10) || 0;
    var lastAuthorKey = thread.getAttribute("data-last-author") || null;
    var url = thread.getAttribute("data-poll-url");
    var typingUrl = thread.getAttribute("data-typing-url");
    var lastTypingSentAt = 0;
    var typingEl = document.createElement("p");
    typingEl.className = "typing";
    typingEl.hidden = true;
    typingEl.textContent = thread.getAttribute("data-typing-label") || "Visitor is typing...";
    thread.appendChild(typingEl);

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
      replyBox.addEventListener("input", function () {
        autogrow();
        noteTyping();
      });
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
        keepTypingLast();
        return;
      }

      var key = message.author + ":" + (message.name || "");
      if (key !== lastAuthorKey) {
        var who = document.createElement("p");
        who.className = "who " + message.author;
        who.textContent = message.name + " · " + message.at;
        thread.appendChild(who);
        keepTypingLast();
        lastAuthorKey = key;
      }
      var bubble = document.createElement("div");
      bubble.className = "msg " + message.author;
      bubble.id = "message-" + message.id;
      if (message.body) bubble.appendChild(document.createTextNode(message.body));
      appendAttachments(bubble, message.attachments);
      thread.appendChild(bubble);
      keepTypingLast();
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
          img.addEventListener("load", keepBottom); // a live image grows the thread
          link.appendChild(img);
        } else if (att.audio) {
          var audio = document.createElement("audio");
          audio.className = "att-audio";
          audio.controls = true;
          audio.preload = "metadata";
          audio.src = att.url;
          audio.setAttribute("aria-label", att.name);
          wrap.appendChild(audio);
          return;
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
          if (!data) return;
          var messages = data.messages || [];
          if (messages.length) messages.forEach(append);
          setTyping(!!data.typing && !messages.some(function (message) { return message.author === "visitor"; }));
          if (atBottom) thread.scrollTop = thread.scrollHeight;
        })
        .catch(function () { /* transient network error — next tick retries */ });
    }

    function setTyping(show) {
      typingEl.hidden = !show;
      keepTypingLast();
      if (show && stick) thread.scrollTop = thread.scrollHeight;
    }

    function keepTypingLast() {
      if (thread.lastChild !== typingEl) thread.appendChild(typingEl);
    }

    function noteTyping() {
      if (!typingUrl || !replyBox.value.trim()) return;
      var now = Date.now();
      if (now - lastTypingSentAt < 3000) return;
      lastTypingSentAt = now;
      fetch(typingUrl, {
        method: "POST",
        headers: csrfHeaders(),
        credentials: "same-origin"
      }).catch(function () { /* typing hints are best-effort */ });
    }

    setInterval(refresh, POLL_MS);
    // Action Cable (opt-in): a nudge fetches new messages at once instead of
    // waiting for the next tick. Polling stays the fallback.
    openCable(thread, refresh);
  }

  function csrfHeaders() {
    var headers = { Accept: "application/json" };
    var token = document.querySelector('meta[name="csrf-token"]');
    if (token) headers["X-CSRF-Token"] = token.content;
    return headers;
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
