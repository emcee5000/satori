// Satori's data model for the web app: the same JSON format and GTD rules as
// the Mac app (see Sources/Satori/Store.swift and Sync.swift).
const Satori = (() => {
  const DAY = 24 * 3600 * 1000;

  // Dates are stored as ISO 8601 without milliseconds, matching the Mac app.
  const iso = (d = new Date()) => new Date(d).toISOString().replace(/\.\d{3}Z$/, "Z");
  const time = s => (s ? new Date(s).getTime() : 0);
  const startOfToday = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };
  const startOfTomorrow = () => new Date(startOfToday().getTime() + DAY);
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() :
    "10000000-1000-4000-8000-100000000000".replace(/[018]/g, c =>
      (c ^ (Math.random() * 16) >> (c / 4)).toString(16))).toUpperCase();

  const emptyData = () => ({
    tasks: [], projects: [], reviewChecks: [], deleted: {},
    contexts: ["@home", "@work", "@computer", "@phone", "@errands", "@anywhere"],
  });

  const isActive = t => !t.completedAt && !t.trashedAt;
  const isScheduled = (t, now = Date.now()) => time(t.deferUntil) > now;
  const isDueByToday = t => !!t.due && time(t.due) < startOfTomorrow().getTime();
  const isOverdue = t => !!t.due && time(t.due) < startOfToday().getTime();

  function project(data, id) { return data.projects.find(p => p.id === id); }
  const projectIsLive = (data, id) => {
    if (!id) return true;
    const p = project(data, id);
    return !p || (!p.completedAt && !p.trashedAt && !p.isSomeday);
  };

  /** The to-dos shown in a list (same rules as Store.tasks(for:) on the Mac). */
  function list(data, view) {
    const now = Date.now();
    const active = data.tasks.filter(isActive);
    if (view.startsWith("project:")) {
      const id = view.slice(8);
      return active.filter(t => t.projectID === id);
    }
    switch (view) {
      case "inbox": return active.filter(t => t.bucket === "inbox");
      case "today": return active.filter(t => !isScheduled(t, now) && t.bucket !== "reference" &&
        t.bucket !== "someday" && (t.starred || isDueByToday(t)));
      case "next": return active.filter(t => t.bucket === "next" && !isScheduled(t, now) && projectIsLive(data, t.projectID));
      case "scheduled": return active.filter(t => isScheduled(t, now)).sort((a, b) => time(a.deferUntil) - time(b.deferUntil));
      case "waiting": return active.filter(t => t.bucket === "waiting" && !isScheduled(t, now));
      case "someday": return active.filter(t => t.bucket === "someday");
      case "reference": return active.filter(t => t.bucket === "reference");
      case "logbook": return data.tasks.filter(t => t.completedAt && !t.trashedAt)
        .sort((a, b) => time(b.completedAt) - time(a.completedAt));
      case "trash": return data.tasks.filter(t => t.trashedAt).sort((a, b) => time(b.trashedAt) - time(a.trashedAt));
      default: return [];
    }
  }

  const activeProjects = data => data.projects.filter(p => !p.completedAt && !p.trashedAt && !p.isSomeday);
  const nextActionCount = (data, p) => list(data, "project:" + p.id).filter(t => t.bucket === "next" && !isScheduled(t)).length;
  const isStalled = (data, p) => !p.completedAt && !p.trashedAt && !p.isSomeday && nextActionCount(data, p) === 0;

  /** Pulls a known "@context" word out of a title, e.g. "Call Bob @phone". */
  function parseContext(data, title) {
    let context = null;
    const words = title.split(" ").filter(w => {
      if (context || !w.startsWith("@")) return true;
      const match = data.contexts.find(c => c.toLowerCase() === w.toLowerCase());
      if (!match) return true;
      context = match;
      return false;
    });
    return { title: words.join(" ").trim(), context };
  }

  function addTask(data, rawTitle, view) {
    const { title, context } = parseContext(data, rawTitle);
    const now = iso();
    const t = { id: uuid(), title, notes: "", bucket: "inbox", waitingOn: "", starred: false, createdAt: now, updatedAt: now };
    if (context) t.context = context;
    if (view === "today") { t.bucket = "next"; t.starred = true; }
    else if (view === "next") t.bucket = "next";
    else if (view === "scheduled") { t.bucket = "next"; t.deferUntil = iso(startOfTomorrow()); }
    else if (["waiting", "someday", "reference"].includes(view)) t.bucket = view;
    else if (view.startsWith("project:")) { t.bucket = "next"; t.projectID = view.slice(8); }
    data.tasks.push(t);
    return t;
  }

  /** Applies a change and bumps updatedAt only if something actually changed. */
  function update(data, id, change) {
    const t = data.tasks.find(x => x.id === id);
    if (!t) return;
    const before = canonical(t);
    change(t);
    for (const k of Object.keys(t)) if (t[k] == null) delete t[k];
    if (canonical(t) !== before) t.updatedAt = iso();
  }

  function updateProject(data, id, change) {
    const p = project(data, id);
    if (!p) return;
    const before = canonical(p);
    change(p);
    for (const k of Object.keys(p)) if (p[k] == null) delete p[k];
    if (canonical(p) !== before) p.updatedAt = iso();
  }

  /** Moves a to-do so it shows up in the given list (same as Store.send on the Mac). */
  function send(data, id, view) {
    update(data, id, t => {
      const unclarified = ["inbox", "someday", "reference"].includes(t.bucket);
      if (view === "today") {
        if (unclarified) t.bucket = "next";
        delete t.deferUntil; t.starred = true;
      } else if (view === "scheduled") {
        if (unclarified) t.bucket = "next";
        if (!isScheduled(t)) t.deferUntil = iso(startOfTomorrow());
        t.starred = false;
      } else if (["inbox", "someday", "reference"].includes(view)) {
        t.bucket = view; delete t.deferUntil; t.starred = false;
      } else if (["next", "waiting"].includes(view)) {
        t.bucket = view; delete t.deferUntil;
      }
    });
  }

  function addProject(data, title) {
    const now = iso();
    const p = { id: uuid(), title, outcome: "", isSomeday: false, createdAt: now, updatedAt: now };
    data.projects.push(p);
    return p;
  }

  function emptyTrash(data) {
    const now = iso();
    data.deleted = data.deleted || {};
    for (const t of data.tasks) if (t.trashedAt) data.deleted[t.id] = now;
    data.tasks = data.tasks.filter(t => !t.trashedAt);
  }

  // ---- Sync ----

  function mergeItems(local, remote, deleted) {
    const remoteByID = new Map(remote.map(x => [x.id, x]));
    const localIDs = new Set(local.map(x => x.id));
    const merged = local.map(x => {
      const other = remoteByID.get(x.id);
      return other && time(other.updatedAt || other.createdAt) > time(x.updatedAt || x.createdAt) ? other : x;
    });
    for (const x of remote) if (!localIDs.has(x.id)) merged.push(x);
    return merged.filter(x => !deleted[x.id]);
  }

  /**
   * Combines two copies: newest edit wins per item, deletions stick, and
   * settings (contexts, review state) come from the Mac copy, since the web
   * app doesn't edit them.
   */
  function merge(local, remote) {
    const out = { ...remote };
    const deleted = { ...(remote.deleted || {}) };
    for (const [id, d] of Object.entries(local.deleted || {})) {
      if (!deleted[id] || time(d) > time(deleted[id])) deleted[id] = d;
    }
    const cutoff = Date.now() - 90 * DAY;
    for (const id of Object.keys(deleted)) if (time(deleted[id]) < cutoff) delete deleted[id];
    out.deleted = deleted;
    out.tasks = mergeItems(local.tasks || [], remote.tasks || [], deleted);
    out.projects = mergeItems(local.projects || [], remote.projects || [], deleted);
    return out;
  }

  /** Stable JSON (sorted keys, no nulls) for comparing two copies. */
  function canonical(value) {
    const norm = v => {
      if (Array.isArray(v)) return v.map(norm);
      if (v && typeof v === "object") {
        const o = {};
        for (const k of Object.keys(v).sort()) if (v[k] != null) o[k] = norm(v[k]);
        return o;
      }
      return v;
    };
    return JSON.stringify(norm(value));
  }

  /** Pretty, key-sorted JSON for writing to GitHub, so diffs stay readable. */
  const pretty = value => JSON.stringify(JSON.parse(canonical(value)), null, 2);

  function toBase64(text) {
    const bytes = new TextEncoder().encode(text);
    let bin = "";
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(bin);
  }
  const fromBase64 = b64 => new TextDecoder().decode(Uint8Array.from(atob(b64.replace(/\s/g, "")), c => c.charCodeAt(0)));

  function friendly(s) {
    const d = new Date(s), today = startOfToday().getTime(), day = new Date(d).setHours(0, 0, 0, 0);
    const diff = Math.round((day - today) / DAY);
    if (diff === 0) return "today";
    if (diff === 1) return "tomorrow";
    if (diff === -1) return "yesterday";
    const opts = { weekday: "short", month: "short", day: "numeric" };
    if (d.getFullYear() !== new Date().getFullYear()) opts.year = "numeric";
    return d.toLocaleDateString(undefined, opts).toLowerCase();
  }

  return {
    iso, time, startOfToday, startOfTomorrow, uuid, emptyData, isActive, isScheduled, isOverdue,
    project, list, activeProjects, nextActionCount, isStalled, parseContext, addTask, update,
    updateProject, send, addProject, emptyTrash, merge, canonical, pretty, toBase64, fromBase64, friendly,
  };
})();

if (typeof module !== "undefined") module.exports = Satori;
