// Satori web app: a lightweight phone companion to Satori for Mac.
// Data lives in localStorage and syncs through a private GitHub repo.
(() => {
  const S = Satori;
  const DATA_KEY = "satori.data";
  const SYNC_KEY = "satori.sync";
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  let data = load();
  let cfg = JSON.parse(localStorage.getItem(SYNC_KEY) || "{}");
  // A setup link from Satori for Mac (Settings → Sync → Connect iPhone) carries the repo and token.
  const linked = S.parseSetupLink(location.hash);
  if (linked) {
    cfg = linked;
    localStorage.setItem(SYNC_KEY, JSON.stringify(cfg));
    history.replaceState(null, "", "#settings");
  }
  let view = location.hash.slice(1) || "inbox";
  let editing = null;
  let sync = { state: cfg.repo && cfg.token ? "idle" : "off", message: "", at: null };

  const LISTS = {
    inbox: { title: "Inbox", color: "--blue", hint: "Capture everything. Clarify it later.", placeholder: "Capture a thought…" },
    today: { title: "Today", color: "--yellow", hint: "Starred actions and anything due today.", placeholder: "Add an action for today" },
    next: { title: "Next Actions", color: "--cyan", hint: "The very next physical action — by context.", placeholder: "Add a next action — start with a verb" },
    scheduled: { title: "Scheduled", color: "--red", hint: "Your tickler. Items reappear on their start date.", placeholder: "Add something for tomorrow" },
    waiting: { title: "Waiting For", color: "--orange", hint: "Things you've delegated or are expecting.", placeholder: "What are you waiting for?" },
    someday: { title: "Someday/Maybe", color: "--sand", hint: "Incubating ideas. Revisit them weekly.", placeholder: "Someday I might…" },
    reference: { title: "Reference", color: "--dim", hint: "Non-actionable information worth keeping.", placeholder: "Add a reference note" },
    projects: { title: "Projects", color: "--magenta", hint: "Every project needs a next action." },
    logbook: { title: "Logbook", color: "--green", hint: "Everything you've finished." },
    trash: { title: "Trash", color: "--faint", hint: "Deleted items. Tap one to put it back." },
    more: { title: "More", color: "--dim", hint: "Everything else." },
    settings: { title: "Sync & Settings", color: "--blue", hint: "Keep your phone and Mac in step." },
  };
  const MOVE_TARGETS = ["inbox", "today", "next", "scheduled", "waiting", "someday", "reference"];

  // ---- Storage ----

  function load() {
    try {
      const d = JSON.parse(localStorage.getItem(DATA_KEY));
      if (d && Array.isArray(d.tasks)) return d;
    } catch {}
    return S.emptyData();
  }
  function persist() { localStorage.setItem(DATA_KEY, JSON.stringify(data)); }
  function save() { persist(); render(); scheduleSync(1000); }

  // ---- Rendering ----

  function go(v) {
    view = v;
    history.replaceState(null, "", "#" + v);
    closeSheet();
    render();
    window.scrollTo(0, 0);
  }

  function render() {
    renderHeader();
    renderMain();
    renderTabs();
    if (editing) renderSheet();
  }

  function info(v) {
    if (v.startsWith("project:")) {
      const p = S.project(data, v.slice(8));
      return { title: p ? p.title || "Untitled Project" : "Project", color: "--magenta",
        hint: p && p.outcome ? p.outcome : "What does “done” look like?", placeholder: "Add an action to this project", back: "projects" };
    }
    return LISTS[v] || LISTS.inbox;
  }

  function syncBadge() {
    if (sync.state === "off") return "";
    if (sync.state === "syncing") return '<span class="sync">syncing…</span>';
    if (sync.state === "error") return '<span class="sync err">⚠ sync</span>';
    if (sync.at) return '<span class="sync ok">synced</span>';
    return "";
  }

  function renderHeader() {
    const i = info(view);
    const isList = MOVE_TARGETS.includes(view) || view.startsWith("project:");
    const n = isList ? S.list(data, view).length : 0;
    $("header").innerHTML = `
      <div class="titlebar">
        ${i.back ? `<button class="back" data-go="${i.back}">‹</button>` : ""}
        <span class="chev" style="color:var(${i.color})">❯</span>
        <h1>${esc(i.title)}</h1>
        ${n ? `<span class="count">${n}</span>` : ""}
        <span id="sync-badge" style="margin-left:auto">${syncBadge()}</span>
      </div>
      <div class="hint"># ${esc(i.hint)}</div>
      ${i.placeholder ? `<form class="capture" id="capture"><span>❯</span>
        <input id="capture-input" enterkeyhint="done" autocomplete="off" placeholder="${esc(i.placeholder)}"></form>` : ""}
      ${view === "projects" ? `<form class="capture" id="new-project"><span>❯</span>
        <input id="project-input" enterkeyhint="done" autocomplete="off" placeholder="New project — name the outcome"></form>` : ""}`;
  }

  function row(t, { showProject = true } = {}) {
    const p = showProject && t.projectID ? S.project(data, t.projectID) : null;
    const meta = [];
    if (p) meta.push(`<span class="proj">▸ ${esc(p.title)}</span>`);
    if (t.context) meta.push(`<span class="ctx">${esc(t.context)}</span>`);
    if (t.bucket === "waiting" && t.waitingOn) meta.push(`<span class="wait">→ ${esc(t.waitingOn)}</span>`);
    if (S.isScheduled(t)) meta.push(`<span class="start">starts ${S.friendly(t.deferUntil)}</span>`);
    if (t.due) meta.push(`<span class="${S.isOverdue(t) ? "over" : ""}">due ${S.friendly(t.due)}</span>`);
    if (S.REPEAT_RULES[t.repeatRule]) meta.push(`↻ ${S.REPEAT_RULES[t.repeatRule]}`);
    if (t.notes) meta.push("≡ note");
    return `<div class="row${t.completedAt ? " done" : ""}" data-open="${t.id}">
      <button class="box" data-check="${t.id}" aria-label="Complete">${t.completedAt ? "[x]" : "[ ]"}</button>
      <div class="t"><div class="title">${esc(t.title || "New To-Do")}</div>
        ${meta.length ? `<div class="meta">${meta.join("  ·  ")}</div>` : ""}</div>
      ${t.starred && !t.completedAt ? '<span class="star">★</span>' : ""}
    </div>`;
  }

  function grouped(tasks, keyOf, order) {
    const groups = new Map();
    for (const t of tasks) {
      const k = keyOf(t);
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(t);
    }
    const keys = order ? order(groups) : [...groups.keys()];
    return keys.map(k => `<div class="section">── ${esc(k)}</div>` + groups.get(k).map(t => row(t)).join("")).join("");
  }

  function empty(title, text) { return `<div class="empty"><b>${title}</b>${text}</div>`; }

  function navRow(v, extra = "") {
    const i = LISTS[v];
    const n = MOVE_TARGETS.includes(v) ? S.list(data, v).length : 0;
    return `<button class="nav-row" data-go="${v}" style="width:100%;text-align:left">
      <span class="dot" style="background:var(${i.color})"></span>${i.title}${extra || (n ? `<span class="n">${n}</span>` : "")}</button>`;
  }

  function renderMain() {
    let html = "";
    if (view === "more") {
      html = ["scheduled", "waiting", "someday", "reference", "logbook", "trash"].map(v => navRow(v)).join("") +
        `<div class="section">── app</div>` + navRow("settings", `<span class="n">${sync.state === "off" ? "off" : sync.state === "error" ? "⚠" : "on"}</span>`);
    } else if (view === "projects") {
      const active = S.activeProjects(data);
      const someday = data.projects.filter(p => !p.completedAt && !p.trashedAt && p.isSomeday);
      const projRow = p => `<button class="nav-row" data-go="project:${p.id}" style="width:100%;text-align:left">
        <span class="dot" style="background:var(--magenta)"></span>${esc(p.title || "Untitled Project")}
        ${S.isStalled(data, p) ? '<span class="warn">! no next action</span>' : `<span class="n">${S.nextActionCount(data, p) || ""}</span>`}</button>`;
      html = active.map(projRow).join("") || empty("No projects", "A project is any outcome that takes more than one step.");
      if (someday.length) html += `<div class="section">── someday/maybe</div>` + someday.map(projRow).join("");
      const done = data.projects.filter(p => p.completedAt && !p.trashedAt)
        .sort((a, b) => S.time(b.completedAt) - S.time(a.completedAt)).slice(0, 10);
      if (done.length) html += `<div class="section">── completed</div>` + done.map(p =>
        `<button class="nav-row" data-go="project:${p.id}" style="width:100%;text-align:left;color:var(--faint)">
          <span style="color:var(--green)">[x]</span>${esc(p.title || "Untitled Project")}<span class="n">${S.friendly(p.completedAt)}</span></button>`).join("");
    } else if (view === "settings") {
      html = settingsHTML();
    } else {
      const tasks = S.list(data, view);
      if (!tasks.length) {
        html = view === "inbox" ? empty("Inbox zero", "Mind like water.")
          : view === "today" ? empty("Nothing for today", "Star a next action to plan it for today.")
          : view.startsWith("project:") ? empty("No actions yet", "What's the very next physical action?")
          : empty("Empty", "");
      } else if (view === "next") {
        html = grouped(tasks, t => t.context || "no context", groups => {
          const known = data.contexts.filter(c => groups.has(c));
          const other = [...groups.keys()].filter(k => k !== "no context" && !data.contexts.includes(k)).sort();
          return [...known, ...other, ...(groups.has("no context") ? ["no context"] : [])];
        });
      } else if (view === "scheduled") {
        html = grouped(tasks, t => S.friendly(t.deferUntil));
      } else if (view === "logbook") {
        html = grouped(tasks, t => S.friendly(t.completedAt));
      } else if (view.startsWith("project:")) {
        const label = t => t.bucket === "inbox" ? "inbox" : S.isScheduled(t) ? "scheduled"
          : ({ next: "next actions", waiting: "waiting for", someday: "someday/maybe", reference: "reference" })[t.bucket];
        const order = ["inbox", "next actions", "waiting for", "scheduled", "someday/maybe", "reference"];
        html = grouped(tasks, label, g => order.filter(k => g.has(k)));
        const p = S.project(data, view.slice(8));
        if (p && S.isStalled(data, p)) html = `<div class="section" style="color:var(--orange)">! no next action — add one above</div>` + html;
      } else {
        html = tasks.map(t => row(t)).join("");
      }
      if (view === "trash" && tasks.length) html += `<div style="padding:16px 6px"><button class="btn danger" id="empty-trash" style="width:100%">Empty Trash</button></div>`;
      if (view.startsWith("project:")) {
        const p = S.project(data, view.slice(8));
        if (p && !p.trashedAt) html += `<div class="project-actions">${p.completedAt
          ? `<button class="btn" data-reopen-project="${p.id}">Reopen project</button>`
          : `<button class="btn" data-complete-project="${p.id}">[x] Complete project</button>`}</div>`;
      }
    }
    $("main").innerHTML = html;
  }

  function renderTabs() {
    const tabs = [["inbox", "▣", "Inbox"], ["today", "★", "Today"], ["next", "❯", "Next"], ["projects", "◎", "Projects"], ["more", "≡", "More"]];
    const current = view.startsWith("project:") ? "projects"
      : ["scheduled", "waiting", "someday", "reference", "logbook", "trash", "settings"].includes(view) ? "more" : view;
    const inboxCount = S.list(data, "inbox").length;
    $("tabs").innerHTML = tabs.map(([v, g, label]) => `<button data-go="${v}" class="${current === v ? "on" : ""}">
      <span class="g">${g}</span>${label}${v === "inbox" && inboxCount ? `<span class="badge">${inboxCount}</span>` : ""}</button>`).join("");
  }

  // ---- Editor sheet ----

  function openSheet(id) { editing = id; renderSheet(); $("sheet").classList.add("open"); $("scrim").classList.add("open"); }
  function closeSheet() {
    editing = null;
    $("sheet").classList.remove("open");
    $("scrim").classList.remove("open");
  }
  const dateValue = s => { if (!s) return ""; const d = new Date(s); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
  const fromDateValue = v => { if (!v) return null; const [y, m, d] = v.split("-").map(Number); return S.iso(new Date(y, m - 1, d)); };

  function currentList(t) {
    if (t.starred && !S.isScheduled(t) && t.bucket !== "someday" && t.bucket !== "reference") return "today";
    if (S.isScheduled(t)) return "scheduled";
    return t.bucket;
  }

  function renderSheet() {
    const t = data.tasks.find(x => x.id === editing);
    if (!t) return closeSheet();
    // Don't rebuild while the user is typing in the sheet.
    if ($("sheet").contains(document.activeElement) && document.activeElement.matches("textarea, input")) return;
    const list = currentList(t);
    const projects = data.projects.filter(p => !p.completedAt && !p.trashedAt);
    $("sheet").innerHTML = `<div class="grab"></div>
      <textarea class="title" id="f-title" rows="2" placeholder="Title">${esc(t.title)}</textarea>
      <div class="label">notes</div>
      <textarea class="notes" id="f-notes" placeholder="Notes">${esc(t.notes || "")}</textarea>
      <div class="label">list</div>
      <div class="chips">${MOVE_TARGETS.map(v => `<button class="chip${list === v ? " on" : ""}" data-send="${v}">${LISTS[v].title}</button>`).join("")}</div>
      ${t.bucket === "waiting" ? `<div class="label">waiting on</div><input type="text" id="f-waiting" placeholder="Person" value="${esc(t.waitingOn || "")}">` : ""}
      <div class="label">context</div>
      <div class="chips"><button class="chip${!t.context ? " on" : ""}" data-ctx="">none</button>
        ${data.contexts.map(c => `<button class="chip${t.context === c ? " on" : ""}" data-ctx="${esc(c)}">${esc(c)}</button>`).join("")}</div>
      <div class="label">project</div>
      <select id="f-project"><option value="">none</option>
        ${projects.map(p => `<option value="${p.id}"${t.projectID === p.id ? " selected" : ""}>${esc(p.title)}</option>`).join("")}</select>
      <div class="dates">
        <div><div class="label">start date</div><input type="date" id="f-start" value="${dateValue(t.deferUntil)}"></div>
        <div><div class="label">due date</div><input type="date" id="f-due" value="${dateValue(t.due)}"></div>
      </div>
      <div class="label">repeat</div>
      <div class="chips"><button class="chip${!t.repeatRule ? " on" : ""}" data-repeat="">never</button>
        ${Object.entries(S.REPEAT_RULES).map(([rule, label]) => `<button class="chip${t.repeatRule === rule ? " on" : ""}" data-repeat="${rule}">${label}</button>`).join("")}</div>
      <div class="actions">
        ${t.trashedAt
          ? `<button class="btn" data-restore="${t.id}">Put Back</button><button class="btn danger" data-destroy="${t.id}">Delete</button>`
          : `<button class="btn danger" data-trash="${t.id}">Trash</button><button class="btn" data-check="${t.id}">${t.completedAt ? "Reopen" : "Complete"}</button>`}
        <button class="btn primary" id="sheet-done">Done</button>
      </div>`;
  }

  // ---- "No more to-dos" prompt ----

  let noticeTimer = null;
  function showNotice(p) {
    $("notice").innerHTML = `<p><b>${esc(p.title || "Untitled Project")}</b> has no more to-dos. Is it done, or what's next?</p>
      <div class="row-btns">
        <button class="btn primary" data-complete-project="${p.id}">Complete</button>
        <button class="btn" data-next-action="${p.id}">Add next action</button>
        <button class="btn" data-dismiss>Not now</button>
      </div>`;
    $("notice").hidden = false;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(hideNotice, 15000);
  }
  function hideNotice() { $("notice").hidden = true; clearTimeout(noticeTimer); }

  // ---- Settings ----

  function syncStatusHTML() {
    return sync.state === "off" ? "Sync is off."
      : sync.state === "syncing" ? "Syncing…"
      : sync.state === "error" ? `<span style="color:var(--red)">⚠ ${esc(sync.message)}</span>`
      : sync.at ? `<span style="color:var(--green)">Synced at ${sync.at.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}</span>` : "Ready.";
  }

  function settingsHTML() {
    return `
      <div class="card"><h3>Sync with your Mac</h3>
        <p>Satori syncs through a private GitHub repo you own. Use the same repo and token as in Satori for Mac → Settings → Sync.</p>
        <label>Setup link<input id="s-link" autocapitalize="off" autocorrect="off" placeholder="Paste from Mac: Settings → Sync → Connect iPhone"></label>
        <p style="margin:0 0 8px">Or enter them yourself:</p>
        <label>Repository<input id="s-repo" autocapitalize="off" autocorrect="off" placeholder="you/satori-data" value="${esc(cfg.repo || "")}"></label>
        <label>Token<input id="s-token" type="password" autocapitalize="off" placeholder="github_pat_…" value="${esc(cfg.token || "")}"></label>
        <button class="btn primary" id="s-save">Save &amp; sync</button>
        <p style="margin-top:12px" id="s-status">${syncStatusHTML()}</p>
        ${cfg.repo ? '<button class="btn" id="s-off">Turn off sync on this phone</button>' : ""}
      </div>
      <div class="card"><h3>Add to your home screen</h3>
        <ol><li>Open this page in Safari.</li><li>Tap <b>Share</b>, then <b>Add to Home Screen</b>.</li></ol>
        <p>Satori then opens full-screen and works offline.</p>
      </div>
      <div class="card"><h3>Your data</h3>
        <p>${data.tasks.length} to-dos and ${data.projects.length} projects are stored on this phone.</p>
        <button class="btn" id="s-export">Export as JSON</button>
      </div>
      <div class="card"><p>Satori is free and open source. <a href="https://github.com/emcee5000/satori">github.com/emcee5000/satori</a></p></div>`;
  }

  // ---- Sync through GitHub ----

  // The last copy fetched from GitHub. Checking it with its ETag is free when nothing changed,
  // which is what makes polling every few seconds affordable.
  let syncTimer = null, syncing = false, syncAgain = false, remoteCache = null;
  function scheduleSync(delay) {
    if (!cfg.repo || !cfg.token) return;
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => { syncTimer = null; runSync(); }, delay);
  }
  // Updates only the status text, so a sync never disturbs what you're typing.
  function setSync(state, message = "") {
    sync.state = state; sync.message = message;
    if (state === "idle") sync.at = new Date();
    const badge = $("sync-badge"), status = $("s-status");
    if (badge) badge.innerHTML = syncBadge();
    if (status) status.innerHTML = syncStatusHTML();
    if (view === "more") renderMain();
  }
  // Shows changes from the Mac without losing a half-typed capture or an open edit.
  function applyRemote() {
    const input = document.activeElement;
    const capture = $("capture-input"), value = capture ? capture.value : "";
    const focused = capture && input === capture;
    renderHeader(); renderMain(); renderTabs();
    if (editing && !$("sheet").contains(input)) renderSheet();
    const again = $("capture-input");
    if (again && value) again.value = value;
    if (again && focused) again.focus();
  }

  async function runSync() {
    if (!cfg.repo || !cfg.token || !navigator.onLine) return;
    if (syncing) { syncAgain = true; return; }
    syncing = true;
    // Only show "syncing…" until the first success, so quiet checks don't flicker.
    if (sync.state !== "idle") setSync("syncing");
    const url = `https://api.github.com/repos/${cfg.repo.trim()}/contents/data.json`;
    const headers = { Authorization: `Bearer ${cfg.token.trim()}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
    const problem = code => code === 401 ? "GitHub rejected the token."
      : code === 403 ? "The token can't write to this repo."
      : code === 404 ? "Repo not found. Check the name and token access."
      : `GitHub returned an error (${code}).`;
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        const get = remoteCache ? { ...headers, "If-None-Match": remoteCache.etag } : headers;
        const res = await fetch(url, { headers: get, cache: "no-store" });
        let remote = null, sha;
        if (res.status === 304 && remoteCache) {
          ({ remote, sha } = remoteCache);
        } else if (res.ok) {
          const file = await res.json();
          sha = file.sha;
          remote = JSON.parse(S.fromBase64(file.content));
          const etag = res.headers.get("ETag");
          remoteCache = etag ? { etag, remote, sha } : null;
        } else if (res.status !== 404) {
          throw new Error(problem(res.status));
        }
        const merged = remote ? S.merge(data, remote) : data;
        if (S.canonical(merged) !== S.canonical(data)) { data = merged; persist(); applyRemote(); }
        if (!remote || S.canonical(merged) !== S.canonical(remote)) {
          const put = await fetch(url, {
            method: "PUT", headers,
            body: JSON.stringify({ message: `Sync from phone: ${S.summary(remote, merged)}`, content: S.toBase64(S.pretty(merged) + "\n"), sha }),
          });
          remoteCache = null;
          if (put.status === 409 || put.status === 422) continue; // someone else wrote first; merge again
          if (!put.ok) throw new Error(problem(put.status));
        }
        setSync("idle");
        return;
      }
      throw new Error("Kept conflicting with another device. Try again.");
    } catch (e) {
      setSync("error", e.message || "Sync failed.");
    } finally {
      syncing = false;
      if (syncAgain) { syncAgain = false; scheduleSync(500); }
    }
  }

  // ---- Events ----

  document.addEventListener("submit", e => {
    e.preventDefault();
    if (e.target.id === "capture") {
      const input = $("capture-input");
      const title = input.value.trim();
      if (!title) return;
      S.addTask(data, title, view);
      input.value = "";
      save();
      $("capture-input").focus();
    } else if (e.target.id === "new-project") {
      const title = $("project-input").value.trim();
      if (!title) return;
      const p = S.addProject(data, title);
      save();
      go("project:" + p.id);
    }
  });

  document.addEventListener("click", e => {
    const el = e.target.closest("[data-check],[data-open],[data-go],[data-send],[data-ctx],[data-repeat],[data-trash],[data-restore],[data-destroy],[data-complete-project],[data-reopen-project],[data-next-action],[data-dismiss],button[id],#scrim");
    if (!el) return;
    const d = el.dataset;
    if (d.check) {
      e.stopPropagation();
      const t = data.tasks.find(x => x.id === d.check);
      if (!t) return;
      if (t.completedAt) { S.update(data, t.id, x => { x.completedAt = null; }); save(); return; }
      el.textContent = "[x]";
      el.closest(".row")?.classList.add("done");
      setTimeout(() => {
        S.complete(data, t.id);
        if (editing === t.id) closeSheet();
        save();
        const p = S.finishedProject(data, t);
        if (p) showNotice(p);
      }, 350);
    } else if (d.open) {
      openSheet(d.open);
    } else if (d.completeProject) {
      const open = S.openTasks(data, d.completeProject).length;
      if (open && !confirm(`Complete this project? Its ${open} open to-do${open === 1 ? "" : "s"} will be marked done too.`)) return;
      S.completeProject(data, d.completeProject); hideNotice(); save(); go("projects");
    } else if (d.reopenProject) {
      S.reopenProject(data, d.reopenProject); save();
    } else if (d.nextAction) {
      hideNotice(); go("project:" + d.nextAction); setTimeout(() => $("capture-input")?.focus(), 50);
    } else if (d.dismiss !== undefined) {
      hideNotice();
    } else if (d.go) {
      go(d.go);
    } else if (d.send) {
      S.send(data, editing, d.send); save(); renderSheet();
    } else if (d.repeat !== undefined) {
      S.update(data, editing, t => { t.repeatRule = d.repeat || null; }); save(); renderSheet();
    } else if (d.ctx !== undefined) {
      S.update(data, editing, t => { t.context = d.ctx || null; }); save(); renderSheet();
    } else if (d.trash) {
      S.update(data, d.trash, t => { t.trashedAt = S.iso(); }); closeSheet(); save();
    } else if (d.restore) {
      S.update(data, d.restore, t => { t.trashedAt = null; }); closeSheet(); save();
    } else if (d.destroy) {
      data.deleted = data.deleted || {};
      data.deleted[d.destroy] = S.iso();
      data.tasks = data.tasks.filter(t => t.id !== d.destroy);
      closeSheet(); save();
    } else if (el.id === "scrim" || el.id === "sheet-done") {
      closeSheet(); render();
    } else if (el.id === "empty-trash") {
      if (confirm("Delete everything in the Trash?")) { S.emptyTrash(data); save(); }
    } else if (el.id === "s-save") {
      cfg = { repo: $("s-repo").value.trim(), token: $("s-token").value.trim() };
      localStorage.setItem(SYNC_KEY, JSON.stringify(cfg));
      remoteCache = null;
      sync.state = cfg.repo && cfg.token ? "idle" : "off";
      runSync();
    } else if (el.id === "s-off") {
      cfg = {}; localStorage.removeItem(SYNC_KEY); sync = { state: "off", message: "", at: null }; render();
    } else if (el.id === "s-export") {
      const blob = new Blob([S.pretty(data)], { type: "application/json" });
      const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "satori-data.json" });
      a.click();
      URL.revokeObjectURL(a.href);
    }
  });

  // Text fields in the sheet save as you type.
  document.addEventListener("input", e => {
    if (e.target.id === "s-link") {
      const linked = S.parseSetupLink(e.target.value);
      $("s-status").innerHTML = linked ? "Link recognised. Tap <b>Save &amp; sync</b>."
        : e.target.value ? '<span style="color:var(--red)">That isn\'t a Satori setup link.</span>' : syncStatusHTML();
      if (linked) { $("s-repo").value = linked.repo; $("s-token").value = linked.token; }
      return;
    }
    if (!editing) return;
    const fields = { "f-title": "title", "f-notes": "notes", "f-waiting": "waitingOn" };
    const key = fields[e.target.id];
    if (key) { S.update(data, editing, t => { t[key] = e.target.value; }); persist(); scheduleSync(1500); }
  });
  document.addEventListener("change", e => {
    if (!editing) return;
    if (e.target.id === "f-project") S.update(data, editing, t => { t.projectID = e.target.value || null; if (t.projectID && t.bucket === "inbox") t.bucket = "next"; });
    else if (e.target.id === "f-start") S.update(data, editing, t => { t.deferUntil = fromDateValue(e.target.value); });
    else if (e.target.id === "f-due") S.update(data, editing, t => { t.due = fromDateValue(e.target.value); });
    else return;
    save();
  });

  // Sync when the app opens or comes back to the foreground, and check for changes every few seconds while open.
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") scheduleSync(200); });
  window.addEventListener("online", () => scheduleSync(200));
  setInterval(() => {
    // Leave a pending upload of local changes to run on its own schedule.
    if (document.visibilityState === "visible" && navigator.onLine && !syncTimer) runSync();
  }, 3000);
  window.addEventListener("hashchange", () => { const v = location.hash.slice(1); if (v && v !== view) go(v); });

  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});

  render();
  scheduleSync(300);
})();
