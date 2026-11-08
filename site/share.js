// The share page (/s/<id>, site/share.html): fetches the shared meeting and draws it. Everything
// from the document goes in with textContent, never as HTML (the page's CSP allows no other script).
// A password share is opened with PBKDF2 of the password; only that, not the password, is sent.
(function () {
  "use strict";
  var T = JSON.parse(document.getElementById("share-text").textContent);
  var id = (location.pathname.match(/^\/s\/([A-Za-z0-9_-]+)/) || [])[1] || "";
  var $ = function (s) { return document.getElementById(s); };
  var doc = null;

  function show(which) {
    ["sh-loading", "sh-password", "sh-gone", "sh-doc"].forEach(function (k) { $(k).hidden = k !== which; });
  }

  function gone(code) {
    var h = { revoked: T.revoked, expired: T.expired, locked: T.locked }[code] || T.missing;
    var p = code === "locked" ? T.locked_p : code === "not_found" ? T.missing_p : T.gone_p;
    $("sh-gone-h").textContent = h;
    $("sh-gone-p").textContent = p;
    show("sh-gone");
  }

  function failed() {
    $("sh-loading").textContent = T.error;
    show("sh-loading");
  }

  function el(tag, text, cls) {
    var e = document.createElement(tag);
    if (text != null) e.textContent = text;
    if (cls) e.className = cls;
    return e;
  }

  function clock(t) {
    t = Math.max(0, Math.floor(t || 0));
    var h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60;
    var two = function (n) { return (n < 10 ? "0" : "") + n; };
    return h ? h + ":" + two(m) + ":" + two(s) : two(m) + ":" + two(s);
  }

  function langName(c) {
    try { return new Intl.DisplayNames([document.documentElement.lang], { type: "language" }).of(c) || c; } catch (e) { return c; }
  }

  function render(d) {
    doc = d;
    document.title = d.title + " · " + document.title.split(" · ").pop();
    $("sh-title").textContent = d.title;
    $("sh-pill").textContent = T.pill + (d.langs.length ? " · " + d.langs.map(langName).join(" → ") : "");
    var when = new Date(d.startedAt);
    var date = isNaN(when) ? "" : when.toLocaleString(document.documentElement.lang, { dateStyle: "medium", timeStyle: "short" });
    $("sh-meta").textContent = [date, T.minutes.replace("{n}", Math.max(1, Math.round(d.duration / 60)))].filter(Boolean).join(" · ");

    var n = d.notes;
    if (n) {
      $("sh-summary").textContent = n.summary;
      fill("sh-conclusions", n.conclusions, function (c) { return el("li", c.text); });
      fill("sh-todos", n.todos, function (c) {
        var li = el("li"), box = el("span", null, "box");
        box.setAttribute("aria-hidden", "true");
        li.appendChild(box);
        li.appendChild(el("span", (c.owner ? c.owner + "：" : "") + c.text));
        return li;
      });
      fill("sh-topics", n.topics, function (t) {
        var box = el("div", null, "sh-topic");
        box.appendChild(el("h4", t.title));
        if (t.summary) box.appendChild(el("p", t.summary));
        if (t.points.length) {
          var ul = el("ul");
          t.points.forEach(function (p) { ul.appendChild(el("li", p)); });
          box.appendChild(ul);
        }
        return box;
      }, ".sh-topic-list");
      fill("sh-terms", n.terms, function (c) {
        var li = el("li");
        li.appendChild(el("b", c.name));
        if (c.note) li.appendChild(document.createTextNode(" " + c.note));
        return li;
      });
    } else {
      $("sh-notes").hidden = true;
    }

    // One translated line, the way the app's subtitle bar shows it.
    var q = d.lines.filter(function (l) { return l.dst && l.dst !== l.src && l.src.length > 12; })[0];
    if (q) {
      $("sh-quote").querySelector(".src").textContent = q.src;
      $("sh-quote").querySelector(".dst").textContent = q.dst;
      $("sh-quote").hidden = false;
    }

    if (d.lines.length) {
      var list = $("sh-line-list");
      d.lines.forEach(function (l) {
        var li = el("li");
        li.appendChild(el("span", clock(l.t), "t"));
        var body = el("div");
        body.appendChild(el("span", l.who, "who"));
        body.appendChild(el("span", l.src, "src"));
        if (l.dst && l.dst !== l.src) body.appendChild(el("span", l.dst, "dst"));
        li.appendChild(body);
        list.appendChild(li);
      });
      $("sh-lines").hidden = false;
    }
    $("sh-hidden").textContent = d.hidden ? T.hidden.replace("{n}", d.hidden) : T.no_audio;
    show("sh-doc");
  }

  function fill(boxId, items, make, inner) {
    if (!items || !items.length) return;
    var box = $(boxId), target = box.querySelector(inner || "ul");
    items.forEach(function (x) { target.appendChild(make(x)); });
    box.hidden = false;
  }

  function notesText() {
    var d = doc, n = d.notes, out = [d.title, $("sh-meta").textContent, ""];
    if (n) {
      if (n.summary) out.push(n.summary, "");
      if (n.conclusions.length) out.push(n.conclusions.map(function (c) { return "- " + c.text; }).join("\n"), "");
      if (n.todos.length) out.push(n.todos.map(function (c) { return "- [ ] " + (c.owner ? c.owner + "：" : "") + c.text; }).join("\n"), "");
      n.topics.forEach(function (t) { out.push(t.title + (t.summary ? "：" + t.summary : "")); t.points.forEach(function (p) { out.push("- " + p); }); out.push(""); });
    }
    out.push(location.href.split("#")[0]);
    return out.join("\n");
  }

  function copy(text, button, done) {
    var label = button.textContent;
    (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(function () {
      button.textContent = done;
      setTimeout(function () { button.textContent = label; }, 2000);
    }, function () { window.prompt("", text); });
  }

  $("sh-forward").addEventListener("click", function () {
    var url = location.href.split("#")[0];
    if (navigator.share) { navigator.share({ title: doc ? doc.title : document.title, url: url }).catch(function () {}); return; }
    copy(url, this, T.link_copied);
  });
  $("sh-copy").addEventListener("click", function () { copy(notesText(), this, T.copied); });
  document.querySelectorAll(".sh-seg button").forEach(function (b) {
    b.addEventListener("click", function () {
      document.querySelectorAll(".sh-seg button").forEach(function (x) { x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
      $("sh-line-list").setAttribute("data-view", b.getAttribute("data-view"));
    });
  });

  function b64(bytes) {
    var s = "";
    new Uint8Array(bytes).forEach(function (c) { s += String.fromCharCode(c); });
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function unb64(t) {
    var s = atob(t.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((t.length + 3) % 4));
    return Uint8Array.from(s, function (c) { return c.charCodeAt(0); });
  }

  function answer(r) {
    if (r.ok) return r.json().then(function (d) { if (d.locked) { lock = d; show("sh-password"); $("sh-pw").focus(); } else render(d); });
    return r.json().then(function (e) {
      if (r.status === 404 || r.status === 410 || r.status === 423) gone(e.code);
      else if (r.status === 403) { $("sh-pw-msg").textContent = T.wrong; $("sh-pw").select(); }
      else if (r.status === 429 && lock) $("sh-pw-msg").textContent = T.wait.replace("{s}", e.retryAfter || 60);
      else failed();
    }, failed);
  }

  var lock = null;
  $("sh-pw-form").addEventListener("submit", function (ev) {
    ev.preventDefault();
    var pw = $("sh-pw").value, button = this.querySelector("button");
    if (!pw || !lock || !crypto.subtle) return;
    button.disabled = true;
    crypto.subtle.importKey("raw", new TextEncoder().encode(pw), "PBKDF2", false, ["deriveBits"]).then(function (key) {
      return crypto.subtle.deriveBits({ name: "PBKDF2", salt: unb64(lock.salt), iterations: lock.iter, hash: "SHA-256" }, key, 256);
    }).then(function (bits) {
      return fetch("/api/v1/s/" + id + "/open", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ verifier: b64(bits) }) });
    }).then(answer, failed).then(function () { button.disabled = false; });
  });

  if (!id) { gone("not_found"); return; }
  fetch("/api/v1/s/" + id).then(answer, failed);
})();
