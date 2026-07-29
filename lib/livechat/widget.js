/*
 * livechat widget — self-contained, no framework, no build step.
 *
 * Reads its config from the <script type="application/json"
 * data-livechat-config> the server renders — re-read on every render so a
 * Turbo visit always reflects the current page's config.
 *
 * Transport is polling, on purpose: it needs nothing from the host app — no
 * Action Cable client, no Turbo, no websocket route. ~4s while the panel is
 * open, ~30s in the background for the launcher badge, and nothing at all
 * for a guest who has never written (there is no thread to poll). Paused
 * whenever the tab is hidden.
 *
 * Turbo Drive swaps the <body>, taking our DOM with it; render() re-mounts
 * on every turbo:load and restores the open panel from sessionStorage.
 */
(function () {
  "use strict";

  var config = readConfig();
  if (!config || window.__livechatLoaded) return;
  window.__livechatLoaded = true;

  var Z = 2147482000;
  var OPEN_POLL_MS = 4000;
  var CLOSED_POLL_MS = 30000;

  var root = null;
  var listEl = null;
  var badgeEl = null;
  var formEl = null;
  var inputEl = null;
  var emailRowEl = null;
  var errorEl = null;
  var fileInputEl = null;
  var filesBarEl = null;
  var recordBtnEl = null;
  var recordingBarEl = null;
  var recordingTimeEl = null;
  // Files the visitor has picked but not yet sent. Sent as multipart; kept
  // out of the JSON path so a text-only message stays a plain JSON POST.
  var pendingFiles = [];
  var mediaRecorder = null;
  var recordingStream = null;
  var recordingChunks = [];
  var recordingStartedAt = 0;
  var recordingTimer = null;
  var recordingCancelled = false;
  var isOpen = false;
  var lastFocused = null;
  var expandBtnEl = null;
  // Desktop-only: a bigger panel, remembered across Turbo visits. Never
  // applied on phones, where the panel is already full-screen.
  var expanded = false;
  // On phones the panel is a full-screen modal (focus trapped, page scroll
  // locked); on desktop it stays a non-modal popover you can chat alongside.
  var mobileModal = window.matchMedia ? window.matchMedia("(max-width: 480px)") : null;
  var savedBodyStyle = null; // body's style while the mobile scroll lock is on
  var savedScrollY = 0;
  // The id of the newest message actually RENDERED into the list — never
  // advanced by background polls, so reopening the panel refetches exactly
  // the messages it hasn't shown yet.
  var lastRenderedId = 0;
  var lastAuthorKey = null; // grouping: show the author header only on change
  var hasThread = false;
  var hasEmail = false;
  var sending = false;
  var pollTimer = null;
  var fetching = false;
  // Action Cable (opt-in). The widget learns its signed stream from the poll
  // response — a per-conversation token it never has to guess — and opens a
  // socket that nudges it to poll the instant a reply lands. cableDisabled
  // latches on a rejected subscription so we fall back to polling for good.
  var cableSocket = null;
  var cableStream = null;
  var cableDisabled = false;

  function ready(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  ready(function () {
    expanded = sessionGet("livechat_expanded") === "1";
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && isOpen) closePanel();
    });
    document.addEventListener("click", handleOpenerClick, true);
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) poll();
      schedulePoll();
    });

    render();
    document.addEventListener("turbo:load", render);

    window.Livechat = { open: openPanel, close: closePanel };
  });

  function readConfig() {
    var el = document.querySelector("script[data-livechat-config]");
    if (!el) return null;
    try {
      return JSON.parse(el.textContent);
    } catch (e) {
      return null;
    }
  }

  function render() {
    config = readConfig() || config;
    injectStyles();
    mount();
    applyBrandColor();
    applyExpanded(); // a Turbo swap makes a fresh root — restore the size class
    syncOpenerBadges(); // a Turbo visit brings fresh openers — restamp them

    if (sessionGet("livechat_open") === "1") {
      openPanel();
    } else {
      // One initial fetch decides everything: thread or not, badge count.
      poll();
      schedulePoll();
    }
  }

  function handleOpenerClick(event) {
    var opener = event.target && event.target.closest
      ? event.target.closest("[data-livechat-open]")
      : null;
    if (!opener) return;
    event.preventDefault();
    event.stopPropagation();
    openPanel(opener.getAttribute("data-livechat-message"));
  }

  // --- mounting ---------------------------------------------------------------

  function mount() {
    if (root && document.body.contains(root)) return;

    isOpen = false;
    lastRenderedId = 0;
    lastAuthorKey = null;
    // A Turbo body swap removes the panel without closePanel() running; the
    // documentElement (and any scroll lock on it) survives the swap.
    unlockScroll();

    root = document.createElement("div");
    root.id = "lvc-root";
    if (config.rtl) root.setAttribute("dir", "rtl");
    // No launcher bubble to clear — the panel sits in the corner instead of
    // hovering 66px above nothing.
    if (!config.launcher) root.className = "lvc-no-launcher";

    if (config.launcher) root.appendChild(buildLauncher());
    document.body.appendChild(root);
  }

  // config.accentColor rebrands the widget. Inline style properties on the
  // root outrank the stylesheet (including its dark-mode override), so the
  // brand color holds in both themes; text flips black/white for contrast.
  function applyBrandColor() {
    if (!root || !config.accentColor) return;
    root.style.setProperty("--lvc-accent", config.accentColor);
    root.style.setProperty("--lvc-accent-text", contrastText(config.accentColor));
  }

  function contrastText(color) {
    var hex = String(color).replace(/^#/, "");
    if (hex.length === 3) hex = hex.replace(/./g, function (c) { return c + c; });
    if (!/^[0-9a-fA-F]{6}$/.test(hex)) return "#fff";
    var luminance = 0.2126 * parseInt(hex.slice(0, 2), 16) +
      0.7152 * parseInt(hex.slice(2, 4), 16) +
      0.0722 * parseInt(hex.slice(4, 6), 16);
    return luminance > 160 ? "#111418" : "#fff";
  }

  function buildLauncher() {
    var button = document.createElement("button");
    button.id = "lvc-launcher";
    button.type = "button";
    button.setAttribute("aria-label", config.labels.launcher);
    button.title = config.labels.launcher;
    button.innerHTML =
      '<svg viewBox="0 0 24 24" width="26" height="26" aria-hidden="true">' +
      '<path fill="currentColor" d="M12 3C6.5 3 2 6.9 2 11.7c0 2.7 1.4 5.1 3.7 6.7-.1' +
      " 1-.6 2.2-1.6 3.2-.2.2 0 .5.2.5 1.9-.1 3.6-.9 4.7-1.7 1 .2 2 .3 3 .3 5.5 0 " +
      '10-3.9 10-8.7S17.5 3 12 3z"/></svg>';

    badgeEl = document.createElement("span");
    badgeEl.id = "lvc-badge";
    badgeEl.hidden = true;
    badgeEl.setAttribute("aria-label", config.labels.unreadAria);
    button.appendChild(badgeEl);

    button.addEventListener("click", function () {
      if (isOpen) closePanel();
      else openPanel();
    });
    return button;
  }

  function buildPanel() {
    var panel = document.createElement("div");
    panel.id = "lvc-panel";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", config.appName);
    panel.addEventListener("keydown", trapFocus);

    var header = document.createElement("div");
    header.id = "lvc-header";
    var titles = document.createElement("div");
    var title = document.createElement("strong");
    title.textContent = config.appName;
    var subtitle = document.createElement("span");
    subtitle.textContent = config.labels.replyTime;
    titles.appendChild(title);
    titles.appendChild(subtitle);
    header.appendChild(titles);

    var actions = document.createElement("div");
    actions.id = "lvc-actions";

    // Grow/shrink the desktop panel. Hidden on phones (already full-screen).
    expandBtnEl = document.createElement("button");
    expandBtnEl.type = "button";
    expandBtnEl.id = "lvc-expand";
    expandBtnEl.addEventListener("click", toggleExpand);
    actions.appendChild(expandBtnEl);

    var close = document.createElement("button");
    close.type = "button";
    close.id = "lvc-close";
    close.setAttribute("aria-label", config.labels.close);
    close.innerHTML = "&times;";
    close.addEventListener("click", closePanel);
    actions.appendChild(close);

    header.appendChild(actions);
    panel.appendChild(header);
    applyExpanded(); // set the panel size + the button's icon/label

    listEl = document.createElement("div");
    listEl.id = "lvc-list";
    listEl.setAttribute("role", "log");
    listEl.setAttribute("aria-live", "polite");
    // The opening greeting, styled as a support message so the panel reads
    // like a conversation that's already been warmly opened. Deliberately a
    // generic team label — never a fake individual, avatar, or presence
    // (livechat is honest async support). It's client-only: never stored,
    // never shown in the agent's inbox.
    var greetingWho = document.createElement("div");
    greetingWho.className = "lvc-who lvc-who-agent";
    greetingWho.textContent = config.labels.team;
    listEl.appendChild(greetingWho);
    var greeting = document.createElement("div");
    greeting.className = "lvc-msg lvc-agent";
    greeting.textContent = config.labels.greeting;
    listEl.appendChild(greeting);
    panel.appendChild(listEl);

    errorEl = document.createElement("div");
    errorEl.id = "lvc-error";
    // The alert region exists before any text lands in it, so screen
    // readers announce the message instead of a silent visual update.
    errorEl.setAttribute("role", "alert");
    errorEl.hidden = true;
    panel.appendChild(errorEl);

    emailRowEl = buildEmailRow();
    panel.appendChild(emailRowEl);

    // The composer is one bordered box: the textarea on top, a toolbar row
    // (tools on the left, send on the right) below — so it reads as a single
    // control, not a textarea flanked by loose buttons.
    formEl = document.createElement("form");
    formEl.id = "lvc-form";

    // Pending-file chips sit at the top of the box, inside the border.
    if (config.attachments) {
      filesBarEl = document.createElement("div");
      filesBarEl.id = "lvc-files";
      filesBarEl.hidden = true;
      formEl.appendChild(filesBarEl);
    }

    inputEl = document.createElement("textarea");
    inputEl.id = "lvc-input";
    inputEl.rows = 1;
    inputEl.placeholder = config.labels.placeholder;
    inputEl.setAttribute("aria-label", config.labels.placeholder);
    inputEl.addEventListener("input", autogrow);
    inputEl.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        send();
      }
    });
    formEl.appendChild(inputEl);

    var toolbar = document.createElement("div");
    toolbar.id = "lvc-toolbar";
    var tools = document.createElement("div");
    tools.id = "lvc-tools";

    // Attachments: a paperclip in the toolbar that opens the file picker.
    if (config.attachments) {
      fileInputEl = document.createElement("input");
      fileInputEl.type = "file";
      fileInputEl.multiple = true;
      fileInputEl.hidden = true;
      fileInputEl.addEventListener("change", function () {
        addFiles(fileInputEl.files);
        fileInputEl.value = ""; // let the same file be re-picked after removal
      });

      var attach = document.createElement("button");
      attach.type = "button";
      attach.id = "lvc-attach";
      attach.className = "lvc-tool";
      attach.setAttribute("aria-label", config.labels.attach);
      attach.title = config.labels.attach;
      // Paperclip (Heroicons, MIT).
      attach.innerHTML =
        '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
        '<path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" ' +
        'stroke-linejoin="round" d="M18.4 8.6 9.9 17a3.5 3.5 0 0 1-5-5l8.5-8.4a2.3 2.3 0 0 1 ' +
        '3.3 3.3l-8.5 8.4a1.1 1.1 0 0 1-1.6-1.6l7.8-7.8"/></svg>';
      attach.addEventListener("click", function () { fileInputEl.click(); });
      tools.appendChild(attach);
      formEl.appendChild(fileInputEl);

      recordBtnEl = document.createElement("button");
      recordBtnEl.type = "button";
      recordBtnEl.id = "lvc-record";
      recordBtnEl.className = "lvc-tool";
      recordBtnEl.setAttribute("aria-label", config.labels.recordAudio);
      recordBtnEl.title = config.labels.recordAudio;
      recordBtnEl.innerHTML =
        '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
        '<path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
        'stroke-linejoin="round" d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3Z' +
        'M5 11a7 7 0 0 0 14 0M12 18v3M8.5 21h7"/></svg>';
      recordBtnEl.addEventListener("click", startRecording);
      tools.appendChild(recordBtnEl);
    }
    toolbar.appendChild(tools);

    var sendButton = document.createElement("button");
    sendButton.type = "submit";
    sendButton.id = "lvc-send";
    sendButton.setAttribute("aria-label", config.labels.send);
    sendButton.title = config.labels.send;
    // Paper airplane (Heroicons, MIT). CSS mirrors it for RTL.
    sendButton.innerHTML =
      '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">' +
      '<path fill="currentColor" d="M3.478 2.404a.75.75 0 0 0-.926.941l2.432 ' +
      "7.905H13.5a.75.75 0 0 1 0 1.5H4.984l-2.432 7.905a.75.75 0 0 0 .926.94 " +
      "60.519 60.519 0 0 0 18.445-8.986.75.75 0 0 0 0-1.218A60.517 60.517 0 0 " +
      '0 3.478 2.404Z"/></svg>';
    toolbar.appendChild(sendButton);

    formEl.appendChild(toolbar);
    if (config.attachments) {
      recordingBarEl = buildRecordingBar();
      formEl.appendChild(recordingBarEl);
    }
    formEl.addEventListener("submit", function (event) {
      event.preventDefault();
      send();
    });

    panel.appendChild(formEl);

    return panel;
  }

  // --- audio recording --------------------------------------------------------

  function buildRecordingBar() {
    var bar = document.createElement("div");
    bar.id = "lvc-recording";
    bar.hidden = true;

    var status = document.createElement("span");
    status.className = "lvc-recording-status";
    var dot = document.createElement("span");
    dot.className = "lvc-recording-dot";
    recordingTimeEl = document.createElement("span");
    recordingTimeEl.textContent = formatDuration(0);
    status.appendChild(dot);
    status.appendChild(recordingTimeEl);
    bar.appendChild(status);

    var actions = document.createElement("div");
    actions.className = "lvc-recording-actions";
    var cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "lvc-recording-cancel";
    cancel.textContent = config.labels.cancelRecording;
    cancel.addEventListener("click", cancelRecording);
    var stop = document.createElement("button");
    stop.type = "button";
    stop.className = "lvc-recording-stop";
    stop.textContent = config.labels.stopRecording;
    stop.addEventListener("click", stopRecording);
    actions.appendChild(cancel);
    actions.appendChild(stop);
    bar.appendChild(actions);
    return bar;
  }

  function recordingSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  }

  function startRecording() {
    if (mediaRecorder) return;
    if (!recordingSupported()) {
      showError(config.labels.microphoneUnsupported);
      return;
    }
    if (pendingFiles.length >= (config.maxAttachments || 5)) {
      showError(config.labels.attachmentError);
      return;
    }

    errorEl.hidden = true;
    if (recordBtnEl) recordBtnEl.disabled = true;
    navigator.mediaDevices.getUserMedia({ audio: true })
      .then(function (stream) {
        var options = preferredAudioOptions();
        recordingChunks = [];
        recordingCancelled = false;
        recordingStream = stream;
        try {
          mediaRecorder = options ? new MediaRecorder(stream, options) : new MediaRecorder(stream);
        } catch (e) {
          stopRecordingTracks();
          throw e;
        }
        mediaRecorder.addEventListener("dataavailable", function (event) {
          if (event.data && event.data.size) recordingChunks.push(event.data);
        });
        mediaRecorder.addEventListener("stop", finishRecording);
        mediaRecorder.start();
        recordingStartedAt = Date.now();
        showRecordingBar(true);
        tickRecording();
        recordingTimer = setInterval(tickRecording, 500);
      })
      .catch(function (error) {
        if (recordBtnEl) recordBtnEl.disabled = false;
        var denied = error && (error.name === "NotAllowedError" || error.name === "SecurityError");
        showError(denied ? config.labels.microphoneDenied : config.labels.microphoneError);
      });
  }

  function preferredAudioOptions() {
    var types = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"];
    if (!window.MediaRecorder || !MediaRecorder.isTypeSupported) return null;
    for (var i = 0; i < types.length; i++) {
      if (MediaRecorder.isTypeSupported(types[i])) return { mimeType: types[i] };
    }
    return null;
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== "inactive") mediaRecorder.stop();
  }

  function cancelRecording() {
    recordingCancelled = true;
    stopRecording();
  }

  function finishRecording() {
    var mimeType = (mediaRecorder && mediaRecorder.mimeType) || "audio/webm";
    stopRecordingTracks();
    clearInterval(recordingTimer);
    recordingTimer = null;
    showRecordingBar(false);
    if (recordBtnEl) recordBtnEl.disabled = false;

    if (!recordingCancelled && recordingChunks.length) {
      pendingFiles.push(audioFile(recordingChunks, mimeType));
      renderFiles();
    }
    mediaRecorder = null;
    recordingChunks = [];
  }

  function stopRecordingTracks() {
    if (!recordingStream) return;
    recordingStream.getTracks().forEach(function (track) { track.stop(); });
    recordingStream = null;
  }

  function showRecordingBar(show) {
    if (recordingBarEl) recordingBarEl.hidden = !show;
    if (recordBtnEl) recordBtnEl.classList.toggle("lvc-recording-on", show);
  }

  function tickRecording() {
    if (!recordingTimeEl) return;
    recordingTimeEl.textContent = config.labels.recording.replace("%{time}", formatDuration(Date.now() - recordingStartedAt));
  }

  function formatDuration(ms) {
    var seconds = Math.max(0, Math.floor(ms / 1000));
    var minutes = Math.floor(seconds / 60);
    seconds = seconds % 60;
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
  }

  function audioFile(chunks, mimeType) {
    var blob = new Blob(chunks, { type: mimeType });
    var extension = audioExtension(mimeType);
    var name = "voice-message-" + new Date().toISOString().replace(/[:.]/g, "-") + "." + extension;
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

  // --- pending attachments ----------------------------------------------------

  function addFiles(fileList) {
    var room = Math.max(0, (config.maxAttachments || 5) - pendingFiles.length);
    for (var i = 0; i < fileList.length && i < room; i++) {
      pendingFiles.push(fileList[i]);
    }
    renderFiles();
  }

  function removeFile(index) {
    pendingFiles.splice(index, 1);
    renderFiles();
  }

  function clearFiles() {
    pendingFiles = [];
    renderFiles();
  }

  function renderFiles() {
    if (!filesBarEl) return;
    filesBarEl.textContent = "";
    filesBarEl.hidden = pendingFiles.length === 0;
    pendingFiles.forEach(function (file, index) {
      var chip = document.createElement("span");
      chip.className = "lvc-chip";
      var name = document.createElement("span");
      name.className = "lvc-chip-name";
      name.textContent = file.name || "voice-message.webm";
      var remove = document.createElement("button");
      remove.type = "button";
      remove.className = "lvc-chip-x";
      remove.setAttribute("aria-label", config.labels.removeFile);
      remove.innerHTML = "&times;";
      remove.addEventListener("click", function () { removeFile(index); });
      chip.appendChild(name);
      chip.appendChild(remove);
      filesBarEl.appendChild(chip);
    });
  }

  // Guests only: one quiet row under the thread asking for an email, shown
  // once they have written and until they save one.
  function buildEmailRow() {
    var row = document.createElement("form");
    row.id = "lvc-email";
    row.setAttribute("aria-live", "polite"); // "we'll also reply by email" is a status
    row.hidden = true;

    var label = document.createElement("span");
    label.textContent = config.labels.emailPrompt;
    var input = document.createElement("input");
    input.type = "email";
    input.required = true;
    input.placeholder = config.labels.emailPlaceholder;
    input.setAttribute("aria-label", config.labels.emailPlaceholder);
    var save = document.createElement("button");
    save.type = "submit";
    save.textContent = config.labels.emailSave;

    row.appendChild(label);
    var controls = document.createElement("div");
    controls.appendChild(input);
    controls.appendChild(save);
    row.appendChild(controls);

    row.addEventListener("submit", function (event) {
      event.preventDefault();
      request("POST", "/email", { email: input.value }).then(function (response) {
        if (response.ok) {
          hasEmail = true;
          label.textContent = config.labels.emailSaved;
          controls.remove();
        }
      });
    });
    return row;
  }

  function autogrow() {
    inputEl.style.height = "auto";
    inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + "px";
  }

  // --- open / close -----------------------------------------------------------

  // prefill (optional string, from data-livechat-message or
  // Livechat.open("…")) seeds the input — but never over a visitor's draft.
  function openPanel(prefill) {
    mount();
    if (!isOpen) {
      isOpen = true;
      lastFocused = document.activeElement;
      sessionSet("livechat_open", "1");

      // The panel is built once and then hidden/shown — closing must never
      // throw away the rendered thread or a half-written message.
      var panel = document.getElementById("lvc-panel");
      if (!panel) {
        panel = buildPanel();
        root.appendChild(panel);
      }
      panel.hidden = false;
      panel.setAttribute("aria-modal", isMobileModal() ? "true" : "false");
      if (isMobileModal()) lockScroll();
      bindViewport(); // pin the panel above the keyboard on phones
      setUnread(0);
      poll();
      schedulePoll();
    }
    if (inputEl) {
      if (typeof prefill === "string" && prefill && !inputEl.value.trim()) {
        inputEl.value = prefill;
        autogrow();
      }
      inputEl.focus();
    }
  }

  function closePanel() {
    isOpen = false;
    sessionSet("livechat_open", "");
    var panel = document.getElementById("lvc-panel");
    if (panel) panel.hidden = true;
    unbindViewport();
    unlockScroll();
    if (lastFocused && document.contains(lastFocused)) lastFocused.focus();
    schedulePoll();
  }

  function isMobileModal() {
    return !!(mobileModal && mobileModal.matches);
  }

  // --- expand / collapse (desktop) --------------------------------------------

  var EXPAND_ICON =
    '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/>' +
    '<line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>';
  var COLLAPSE_ICON =
    '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<polyline points="4 14 10 14 10 20"/><polyline points="20 10 14 10 14 4"/>' +
    '<line x1="14" y1="10" x2="21" y2="3"/><line x1="10" y1="14" x2="3" y2="21"/></svg>';

  function toggleExpand() {
    if (isMobileModal()) return;
    expanded = !expanded;
    sessionSet("livechat_expanded", expanded ? "1" : "");
    applyExpanded();
  }

  // Reflect the current state onto the panel and the header button. A no-op on
  // phones — the class is never added there, so the full-screen panel stands.
  function applyExpanded() {
    var on = expanded && !isMobileModal();
    if (root) root.classList.toggle("lvc-expanded", on);
    if (!expandBtnEl) return;
    var label = on ? config.labels.collapse : config.labels.expand;
    expandBtnEl.setAttribute("aria-label", label);
    expandBtnEl.title = label;
    expandBtnEl.innerHTML = on ? COLLAPSE_ICON : EXPAND_ICON;
  }

  // Tab cycles inside the panel only while it is the full-screen mobile
  // modal; the desktop popover deliberately lets focus reach the page.
  function trapFocus(event) {
    if (event.key !== "Tab" || !isMobileModal()) return;
    var panel = document.getElementById("lvc-panel");
    var focusable = panel.querySelectorAll("button, [href], input, textarea, select");
    if (!focusable.length) return;
    var first = focusable[0];
    var last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  // A real iOS scroll lock. `overflow:hidden` on <html> is ignored by Safari
  // for touch scrolling, so the page slid behind the full-screen panel — and
  // because the panel has no backdrop, that scrolling showed through as the
  // pinned panel chased visualViewport.offsetTop. Pinning <body> with
  // position:fixed genuinely freezes the page (offsetTop then stays 0 and the
  // panel covers the visible area exactly). We snapshot the body's style and
  // scroll position and restore both on unlock. Mobile modal only; the desktop
  // popover never locks.
  function lockScroll() {
    if (savedBodyStyle !== null) return;
    savedScrollY = window.pageYOffset || document.documentElement.scrollTop || 0;
    savedBodyStyle = document.body.getAttribute("style") || "";
    var s = document.body.style;
    s.position = "fixed";
    s.top = -savedScrollY + "px";
    s.left = "0";
    s.right = "0";
    s.width = "100%";
    s.overflow = "hidden";
  }

  function unlockScroll() {
    if (savedBodyStyle === null) return;
    document.body.setAttribute("style", savedBodyStyle);
    savedBodyStyle = null;
    window.scrollTo(0, savedScrollY);
  }

  // --- mobile keyboard: keep the full-screen panel above the keyboard ---------

  // On phones the panel is position:fixed at height:100dvh. When the composer
  // is focused, iOS Safari draws the keyboard OVER that fixed box without
  // resizing it — the send row ends up hidden behind the keyboard and the
  // layout breaks. The visualViewport API reports the actually-visible
  // rectangle (viewport minus keyboard), so we pin the panel to it: its height
  // shrinks to the visible area and its top follows any viewport offset, which
  // sits the composer just above the keyboard. Desktop never runs this — the
  // work is gated on the mobile media query, and we clear the inline styles the
  // moment it stops matching (e.g. a phone rotated to a wide viewport).
  function syncViewport() {
    var panel = document.getElementById("lvc-panel");
    if (!panel || !window.visualViewport) return;
    if (isMobileModal()) {
      panel.style.height = window.visualViewport.height + "px";
      panel.style.top = window.visualViewport.offsetTop + "px";
      scrollToBottom(); // newest message stays in view above the keyboard
    } else {
      // Not the mobile modal — hand height/top back to the stylesheet.
      panel.style.height = "";
      panel.style.top = "";
    }
  }

  function bindViewport() {
    if (!window.visualViewport) return; // older browsers: no-op, CSS stands
    window.visualViewport.addEventListener("resize", syncViewport);
    window.visualViewport.addEventListener("scroll", syncViewport);
    syncViewport(); // apply once on open (covers a keyboard already up)
  }

  function unbindViewport() {
    if (!window.visualViewport) return;
    window.visualViewport.removeEventListener("resize", syncViewport);
    window.visualViewport.removeEventListener("scroll", syncViewport);
    var panel = document.getElementById("lvc-panel");
    if (panel) {
      panel.style.height = "";
      panel.style.top = "";
    }
  }

  // --- polling ----------------------------------------------------------------

  function schedulePoll() {
    if (pollTimer) clearTimeout(pollTimer);
    if (document.hidden) return;
    // A guest who never wrote has no thread: nothing to poll for.
    if (!isOpen && !hasThread && !config.authenticated) return;

    pollTimer = setTimeout(function () {
      poll();
      schedulePoll();
    }, isOpen ? OPEN_POLL_MS : CLOSED_POLL_MS);
  }

  function poll() {
    if (fetching) return;
    fetching = true;

    request("GET", "/conversation?after=" + lastRenderedId)
      .then(function (response) { return response.ok ? response.json() : null; })
      .then(function (data) {
        fetching = false;
        if (!data) return;

        hasThread = data.status !== null;
        hasEmail = !!data.email;
        if (data.cable) ensureCable(data.cable);

        if (isOpen) {
          // Only an open panel renders (and thereby "consumes") messages;
          // while closed, the poll feeds the badge and nothing else.
          (data.messages || []).forEach(appendMessage);
          if (data.unread > 0) request("POST", "/read");
          setUnread(0);
          syncEmailRow();
        } else {
          setUnread(data.unread || 0);
        }
      })
      .catch(function () { fetching = false; });
  }

  var unreadCount = 0;

  function setUnread(count) {
    unreadCount = count;
    if (badgeEl) {
      badgeEl.hidden = !(count > 0);
      badgeEl.textContent = count > 9 ? "9+" : String(count);
    }
    syncOpenerBadges();
  }

  // Hosts that hide the launcher still get an unread indicator: every
  // data-livechat-open element carries a small count badge while replies
  // are waiting, and loses it the moment the panel opens.
  function syncOpenerBadges() {
    var openers = document.querySelectorAll("[data-livechat-open]");
    for (var i = 0; i < openers.length; i++) {
      var badge = openers[i].querySelector(".lvc-opener-badge");
      if (unreadCount > 0) {
        if (!badge) {
          badge = document.createElement("span");
          badge.className = "lvc-opener-badge";
          openers[i].appendChild(badge);
        }
        badge.textContent = unreadCount > 9 ? "9+" : String(unreadCount);
      } else if (badge) {
        badge.remove();
      }
    }
  }

  function syncEmailRow() {
    if (!emailRowEl) return;
    emailRowEl.hidden = !(hasThread && !hasEmail && !config.authenticated);
  }

  // --- messages ---------------------------------------------------------------

  function appendMessage(message) {
    if (!listEl || message.id <= lastRenderedId) return;
    lastRenderedId = message.id;

    if (message.author === "system") {
      var line = document.createElement("div");
      line.className = "lvc-system";
      line.textContent = message.event === "resolved"
        ? config.labels.eventResolved
        : config.labels.eventReopened;
      listEl.appendChild(line);
      lastAuthorKey = null;
      scrollToBottom();
      return;
    }

    // The author header appears only when the sender changes — a run of
    // messages from the same person reads as one block.
    var authorKey = message.author + ":" + (message.label || "");
    if (authorKey !== lastAuthorKey) {
      var who = document.createElement("div");
      who.className = "lvc-who lvc-who-" + message.author;
      who.textContent = message.author === "visitor"
        ? config.labels.you
        : (message.label || config.labels.team);
      listEl.appendChild(who);
      lastAuthorKey = authorKey;
    }

    var bubble = document.createElement("div");
    bubble.className = "lvc-msg lvc-" + message.author;
    if (message.body) bubble.appendChild(document.createTextNode(message.body));
    renderAttachments(bubble, message.attachments);
    bubble.title = new Date(message.at).toLocaleString();
    listEl.appendChild(bubble);
    scrollToBottom();
  }

  // Images show inline (a thumbnail linking to the full file); everything
  // else is a labelled download link. Both hit the engine's gated route.
  function renderAttachments(bubble, attachments) {
    if (!attachments || !attachments.length) return;
    var wrap = document.createElement("div");
    wrap.className = "lvc-atts";
    attachments.forEach(function (att) {
      var link = document.createElement("a");
      link.href = att.url;
      link.target = "_blank";
      link.rel = "noopener";
      if (att.image) {
        link.className = "lvc-att-img";
        var img = document.createElement("img");
        img.src = att.url;
        img.alt = att.name;
        img.loading = "lazy";
        // The image loads after its bubble is placed and grows the panel —
        // re-pin to the bottom so a just-arrived image stays in view.
        img.addEventListener("load", scrollToBottom);
        link.appendChild(img);
      } else if (att.audio) {
        var audio = document.createElement("audio");
        audio.className = "lvc-att-audio";
        audio.controls = true;
        audio.preload = "metadata";
        audio.src = att.url;
        audio.setAttribute("aria-label", att.name);
        wrap.appendChild(audio);
        return;
      } else {
        link.className = "lvc-att-file";
        link.textContent = att.name;
      }
      wrap.appendChild(link);
    });
    bubble.appendChild(wrap);
  }

  function scrollToBottom() {
    if (listEl) listEl.scrollTop = listEl.scrollHeight;
  }

  // --- realtime (optional) ----------------------------------------------------

  // A tiny Action Cable client over the native WebSocket protocol — no
  // @rails/actioncable dependency, no build step. Opens once per conversation
  // stream; a data message is a nudge, so we just poll() through the normal
  // gated path. Polling keeps running regardless, so this only ever makes the
  // widget faster, never load-bearing.
  function ensureCable(info) {
    if (cableDisabled || !info.stream || !window.WebSocket) return;
    if (cableStream === info.stream && cableSocket) return; // already connected

    cableStream = info.stream;
    var identifier = JSON.stringify({
      channel: "Livechat::StreamChannel", signed_stream: info.stream
    });
    try {
      if (cableSocket) cableSocket.close();
      var proto = window.location.protocol === "https:" ? "wss://" : "ws://";
      cableSocket = new WebSocket(proto + window.location.host + info.url, ["actioncable-v1-json"]);
    } catch (e) {
      cableSocket = null;
      return;
    }

    cableSocket.onmessage = function (event) {
      var data;
      try { data = JSON.parse(event.data); } catch (e) { return; }
      if (data.type === "welcome") {
        cableSocket.send(JSON.stringify({ command: "subscribe", identifier: identifier }));
      } else if (data.type === "reject_subscription") {
        cableDisabled = true; // never retry; polling carries on
        if (cableSocket) cableSocket.close();
      } else if (data.message) {
        poll();
      }
    };
    cableSocket.onclose = function () {
      cableSocket = null;
      // Allow a reconnect on the next poll unless the server rejected us.
      if (!cableDisabled) cableStream = null;
    };
  }

  function send() {
    var body = (inputEl.value || "").trim();
    if (mediaRecorder || (!body && !pendingFiles.length) || sending) return;
    sending = true;
    errorEl.hidden = true;
    var button = formEl.querySelector("button[type=submit]");
    button.disabled = true;

    request("POST", "/messages", buildMessagePayload(body))
      .then(function (response) {
        return response.json().then(function (data) {
          return { ok: response.ok, data: data };
        });
      })
      .then(function (result) {
        sending = false;
        button.disabled = false;
        if (result.ok) {
          inputEl.value = "";
          autogrow();
          clearFiles();
          hasThread = true;
          appendMessage(result.data.message);
          syncEmailRow();
          inputEl.focus();
        } else {
          showError((result.data.errors || [])[0] || config.labels.errorSend);
        }
      })
      .catch(function () {
        sending = false;
        button.disabled = false;
        showError(config.labels.errorSend);
      });
  }

  // Multipart only when there are files to carry — otherwise a plain JSON
  // object, so text-only sends stay exactly as they were.
  function buildMessagePayload(body) {
    if (!pendingFiles.length) {
      return { body: body, page_url: window.location.href, locale: config.locale };
    }
    var form = new FormData();
    form.append("body", body);
    form.append("page_url", window.location.href);
    form.append("locale", config.locale);
    pendingFiles.forEach(function (file) { form.append("files[]", file, file.name || "voice-message.webm"); });
    return form;
  }

  function showError(text) {
    errorEl.textContent = text;
    errorEl.hidden = false;
  }

  // --- transport --------------------------------------------------------------

  function request(method, path, body) {
    var options = {
      method: method,
      headers: { "Accept": "application/json" },
      credentials: "same-origin"
    };
    if (method !== "GET") {
      var token = document.querySelector('meta[name="csrf-token"]');
      if (token) options.headers["X-CSRF-Token"] = token.content;
      if (body instanceof FormData) {
        // Let the browser set multipart Content-Type with its boundary.
        options.body = body;
      } else {
        options.headers["Content-Type"] = "application/json";
        options.body = JSON.stringify(body || {});
      }
    }
    return fetch(config.endpoint + path, options);
  }

  // --- session state (survives Turbo visits; try/catch for private modes) ------

  function sessionGet(key) {
    try { return window.sessionStorage.getItem(key); } catch (e) { return null; }
  }

  function sessionSet(key, value) {
    try {
      if (value) window.sessionStorage.setItem(key, value);
      else window.sessionStorage.removeItem(key);
    } catch (e) { /* storage unavailable — open state just won't persist */ }
  }

  // --- styles -------------------------------------------------------------------

  function injectStyles() {
    var css =
      "#lvc-root{--lvc-accent:#2563eb;--lvc-accent-text:#fff;--lvc-surface:#fff;" +
      "--lvc-text:#1c2024;--lvc-muted:#6b7280;--lvc-border:#e5e7eb;--lvc-bg:#f6f7f9;" +
      "font:14px/1.45 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--lvc-text)}" +
      "@media(prefers-color-scheme:dark){#lvc-root{--lvc-surface:#1a1f26;--lvc-text:#e6e8ea;" +
      "--lvc-muted:#9aa2ab;--lvc-border:#2a313a;--lvc-bg:#111418;--lvc-accent:#3b82f6}}" +
      "#lvc-root *{box-sizing:border-box;margin:0;padding:0}" +
      "#lvc-launcher{position:fixed;bottom:20px;right:20px;z-index:" + Z + ";width:54px;height:54px;" +
      "border-radius:50%;border:none;background:var(--lvc-accent);color:var(--lvc-accent-text);" +
      "cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.25);display:flex;align-items:center;" +
      "justify-content:center}" +
      "#lvc-launcher:hover{filter:brightness(1.08)}" +
      "#lvc-root[dir=rtl] #lvc-launcher{right:auto;left:20px}" +
      "#lvc-badge{position:absolute;top:-4px;right:-4px;min-width:20px;height:20px;padding:0 5px;" +
      "border-radius:999px;background:#dc2626;color:#fff;font-size:12px;font-weight:700;" +
      "line-height:20px;text-align:center}" +
      "#lvc-panel{position:fixed;bottom:86px;right:20px;z-index:" + Z + ";width:360px;max-width:calc(100vw - 24px);" +
      "height:520px;max-height:calc(100dvh - 110px);background:var(--lvc-surface);border:1px solid var(--lvc-border);" +
      "border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.28);display:flex;flex-direction:column;overflow:hidden}" +
      "#lvc-panel[hidden]{display:none}" +
      "#lvc-root[dir=rtl] #lvc-panel{right:auto;left:20px}" +
      "#lvc-root.lvc-no-launcher #lvc-panel{bottom:20px;max-height:calc(100dvh - 40px)}" +
      // position/z-index keep the header above the scrolling list, and
      // flex-shrink:0 stops it collapsing — together they stop a message
      // bubble from bleeding over the header's rounded bottom edge.
      "#lvc-header{position:relative;z-index:2;flex-shrink:0;display:flex;align-items:flex-start;" +
      "justify-content:space-between;gap:8px;padding:14px 16px;background:var(--lvc-accent);" +
      "color:var(--lvc-accent-text)}" +
      "#lvc-header strong{display:block;font-size:15px}" +
      "#lvc-header span{display:block;font-size:12px;opacity:.85;margin-top:2px}" +
      "#lvc-actions{display:flex;align-items:center;gap:2px}" +
      "#lvc-close{border:none;background:none;color:var(--lvc-accent-text);font-size:22px;" +
      "line-height:1;cursor:pointer;padding:2px 6px;border-radius:6px}" +
      "#lvc-close:hover{background:rgba(255,255,255,.15)}" +
      "#lvc-root #lvc-expand{border:none;background:none;color:var(--lvc-accent-text);cursor:pointer;" +
      "padding:5px 6px;border-radius:6px;display:flex;align-items:center;justify-content:center;opacity:.9}" +
      "#lvc-root #lvc-expand:hover{background:rgba(255,255,255,.15);opacity:1}" +
      // Desktop only: a roomier panel for long threads and image-heavy chats.
      // Guarded by min-width so it can never shrink the full-screen mobile panel.
      "@media(min-width:481px){#lvc-root.lvc-expanded #lvc-panel{width:min(460px,92vw);" +
      "height:min(680px,88dvh);max-height:88dvh}}" +
      // min-height:0 lets this flex child actually scroll within the panel
      // instead of overflowing it (the classic flexbox scroll gotcha).
      "#lvc-list{flex:1;min-height:0;overflow-y:auto;overscroll-behavior:contain;padding:14px;" +
      "background:var(--lvc-bg);display:flex;flex-direction:column;gap:4px}" +
      // Class rules carry the #lvc-root prefix so they outrank the
      // id-level `#lvc-root *` reset above.
      "#lvc-root .lvc-who{font-size:11px;color:var(--lvc-muted);margin:8px 4px 2px}" +
      "#lvc-root .lvc-who-visitor{text-align:right}" +
      "#lvc-root[dir=rtl] .lvc-who-visitor{text-align:left}" +
      "#lvc-root .lvc-msg{max-width:82%;padding:8px 12px;border-radius:14px;white-space:pre-wrap;" +
      "overflow-wrap:anywhere;font-size:14px}" +
      "#lvc-root .lvc-visitor{align-self:flex-end;background:var(--lvc-accent);color:var(--lvc-accent-text);" +
      "border-bottom-right-radius:4px}" +
      "#lvc-root[dir=rtl] .lvc-visitor{align-self:flex-start;border-bottom-right-radius:14px;" +
      "border-bottom-left-radius:4px}" +
      "#lvc-root .lvc-agent{align-self:flex-start;background:var(--lvc-surface);border:1px solid var(--lvc-border);" +
      "border-bottom-left-radius:4px}" +
      "#lvc-root[dir=rtl] .lvc-agent{align-self:flex-end;border-bottom-left-radius:14px;" +
      "border-bottom-right-radius:4px}" +
      "#lvc-root .lvc-system{align-self:center;color:var(--lvc-muted);font-size:12px;margin:8px 0}" +
      "#lvc-error{padding:6px 14px;color:#dc2626;font-size:13px}" +
      "#lvc-email{padding:8px 14px;border-top:1px solid var(--lvc-border);font-size:12px;" +
      "color:var(--lvc-muted)}" +
      "#lvc-email div{display:flex;gap:6px;margin-top:6px}" +
      "#lvc-email input{flex:1;padding:6px 8px;border:1px solid var(--lvc-border);border-radius:8px;" +
      "background:var(--lvc-bg);color:var(--lvc-text);font:inherit}" +
      "#lvc-email button{padding:6px 10px;border:1px solid var(--lvc-border);border-radius:8px;" +
      "background:var(--lvc-surface);color:var(--lvc-text);font:inherit;cursor:pointer}" +
      // The composer is one bordered box (Intercom-style): textarea on top, a
      // toolbar row below. focus-within lights the whole box, so it reads as a
      // single control.
      "#lvc-form{display:flex;flex-direction:column;gap:6px;margin:10px 12px;padding:8px 10px;" +
      "border:1px solid var(--lvc-border);border-radius:16px;background:var(--lvc-bg)}" +
      // A single, quiet accent border on focus — no extra ring.
      "#lvc-form:focus-within{border-color:var(--lvc-accent)}" +
      // appearance:none flattens Safari's default textarea bevel, which would
      // otherwise show as a second inset box inside the composer.
      "#lvc-root #lvc-input{-webkit-appearance:none;appearance:none;border:none;background:none;" +
      "resize:none;font:inherit;color:var(--lvc-text);padding:4px 4px 0;max-height:120px;outline:none}" +
      "#lvc-toolbar{display:flex;align-items:center;justify-content:space-between;gap:8px}" +
      "#lvc-tools{display:flex;align-items:center;gap:2px}" +
      // Tool buttons (attach, and room for more) are quiet — the accent is the
      // send button's alone.
      "#lvc-root .lvc-tool{border:none;background:none;color:var(--lvc-muted);width:32px;height:32px;" +
      "display:flex;align-items:center;justify-content:center;cursor:pointer;border-radius:8px;padding:0}" +
      "#lvc-root .lvc-tool:hover{background:var(--lvc-border);color:var(--lvc-text)}" +
      "#lvc-root #lvc-record.lvc-recording-on{color:#dc2626}" +
      "#lvc-send{border:none;border-radius:50%;background:var(--lvc-accent);color:var(--lvc-accent-text);" +
      "width:32px;height:32px;min-width:32px;display:flex;align-items:center;justify-content:center;" +
      "cursor:pointer;padding:0}" +
      "#lvc-send:disabled{opacity:.5;cursor:default}" +
      "#lvc-root[dir=rtl] #lvc-send svg{transform:scaleX(-1)}" +
      // Pending-file chips ride at the top of the composer box.
      "#lvc-files{display:flex;flex-wrap:wrap;gap:6px;padding:2px 2px 0}" +
      "#lvc-files[hidden]{display:none}" +
      "#lvc-root .lvc-chip{display:inline-flex;align-items:center;gap:6px;max-width:100%;" +
      "padding:4px 6px 4px 10px;border:1px solid var(--lvc-border);border-radius:999px;" +
      "background:var(--lvc-bg);font-size:12px}" +
      "#lvc-root .lvc-chip-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:180px}" +
      "#lvc-root .lvc-chip-x{border:none;background:none;color:var(--lvc-muted);font-size:16px;" +
      "line-height:1;cursor:pointer;padding:0 2px}" +
      "#lvc-root .lvc-chip-x:hover{color:var(--lvc-text)}" +
      "#lvc-recording{display:flex;align-items:center;justify-content:space-between;gap:8px;" +
      "padding:6px 4px 0;color:var(--lvc-muted);font-size:12px}" +
      "#lvc-recording[hidden]{display:none}" +
      "#lvc-root .lvc-recording-status{display:inline-flex;align-items:center;gap:6px}" +
      "#lvc-root .lvc-recording-dot{width:8px;height:8px;border-radius:50%;background:#dc2626}" +
      "#lvc-root .lvc-recording-actions{display:flex;align-items:center;gap:4px}" +
      "#lvc-root .lvc-recording-actions button{border:1px solid var(--lvc-border);border-radius:8px;" +
      "background:var(--lvc-surface);color:var(--lvc-text);font:inherit;font-size:12px;line-height:1;" +
      "padding:6px 8px;cursor:pointer}" +
      "#lvc-root .lvc-recording-stop{border-color:#dc2626;color:#dc2626}" +
      // Attachments inside a message bubble: thumbnails and file links.
      "#lvc-root .lvc-atts{display:flex;flex-direction:column;gap:6px;margin-top:6px}" +
      "#lvc-root .lvc-att-img{display:block}" +
      "#lvc-root .lvc-att-img img{max-width:100%;max-height:220px;border-radius:8px;display:block}" +
      "#lvc-root .lvc-att-audio{display:block;width:240px;max-width:100%;height:36px}" +
      "#lvc-root .lvc-att-file{display:inline-block;padding:6px 10px;border-radius:8px;" +
      "background:rgba(0,0,0,.06);color:inherit;text-decoration:none;font-size:13px;" +
      "overflow-wrap:anywhere}" +
      "#lvc-root .lvc-att-file:hover{text-decoration:underline}" +
      "#lvc-root .lvc-visitor .lvc-att-file{background:rgba(255,255,255,.2)}" +
      // Phones get the whole screen — a chat is an app screen, not a popup.
      // Selectors repeat the id twice so they outrank the rtl/no-launcher
      // desktop rules regardless of source order.
      "@media(max-width:480px){" +
      "#lvc-root #lvc-panel,#lvc-root[dir=rtl] #lvc-panel,#lvc-root.lvc-no-launcher #lvc-panel" +
      "{left:0;right:0;top:0;bottom:0;width:100%;max-width:100%;height:100dvh;max-height:100dvh;" +
      "border-radius:0;border:none}" +
      // The panel is already full-screen here, so there's nothing to expand.
      // Two ids to outrank the base `#lvc-root #lvc-expand{display:flex}` rule —
      // a bare `#lvc-expand` loses on specificity and never hides.
      "#lvc-root #lvc-expand{display:none}" +
      // 16px stops iOS Safari from zoom-jumping into focused fields.
      "#lvc-root #lvc-input,#lvc-root #lvc-email input{font-size:16px}" +
      // Keep the composer box above the iPhone home indicator.
      "#lvc-root #lvc-form{margin-bottom:calc(10px + env(safe-area-inset-bottom))}" +
      "}" +
      // Lives in host DOM (on data-livechat-open elements), so no #lvc-root prefix.
      ".lvc-opener-badge{display:inline-flex;min-width:18px;height:18px;padding:0 5px;" +
      "margin-inline-start:6px;border-radius:999px;background:#dc2626;color:#fff;" +
      "font-size:11px;font-weight:700;line-height:18px;align-items:center;" +
      "justify-content:center;vertical-align:middle}";

    // Re-inject only when the stylesheet content actually changed. Turbo keeps
    // <head> across visits, so a tab that transitions from an old widget build
    // to a new one (a shipped update) would otherwise keep the stale <style>
    // and pin old CSS even while fresh widget.js runs. Comparing content makes
    // the styles as self-freshening as the fingerprinted script URL.
    var existing = document.getElementById("lvc-styles");
    if (existing && existing.textContent === css) return;
    if (existing) existing.remove();

    var style = document.createElement("style");
    style.id = "lvc-styles";
    style.textContent = css;
    document.head.appendChild(style);
  }
})();
