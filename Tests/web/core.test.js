// Tests for the web app's data logic (site/app/core.js). Run with: node --test Tests/web
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const S = require("../../site/app/core.js");

const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, "../fixtures/recurrence.json"), "utf8"));
/** Local midnight on a "yyyy-mm-dd" day. */
const day = s => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
const dayString = s => {
  if (!s) return undefined;
  const d = new Date(s);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const task = (title, extra = {}) => ({ id: S.uuid(), title, bucket: "inbox", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", ...extra });
const data = (tasks = [], extra = {}) => ({ ...S.emptyData(), tasks, ...extra });

test("nextDate matches the cases shared with the Mac", () => {
  for (const c of fixture.nextDate) {
    assert.equal(dayString(S.nextDate(day(c.from), c.rule)), c.next, JSON.stringify(c));
  }
});

test("nextOccurrence matches the cases shared with the Mac", () => {
  for (const c of fixture.nextOccurrence) {
    const now = new Date(day(c.today).getTime() + 12 * 3600 * 1000);
    const t = task("Repeat", { repeatRule: c.rule });
    if (c.due) t.due = S.iso(day(c.due));
    if (c.start) t.deferUntil = S.iso(day(c.start));
    const next = S.nextOccurrence(t, now);
    assert.ok(next, c.name);
    assert.equal(dayString(next.due), c.nextDue, c.name);
    assert.equal(dayString(next.deferUntil), c.nextStart, c.name);
    assert.notEqual(next.id, t.id);
    assert.equal(next.completedAt, undefined);
    assert.equal(next.repeatRule, c.rule);
  }
});

test("completing a repeating to-do adds the next one; others don't", () => {
  const d = data([task("Water plants", { bucket: "next", repeatRule: "weekly" }), task("Once")]);
  S.complete(d, d.tasks[0].id);
  S.complete(d, d.tasks[1].id);
  assert.equal(d.tasks.length, 3);
  assert.ok(d.tasks[0].completedAt && d.tasks[1].completedAt);
  assert.equal(d.tasks[2].title, "Water plants");
  assert.equal(d.tasks[2].completedAt, undefined);
  assert.equal(S.complete(d, d.tasks[0].id), null, "completing twice does nothing");
  assert.equal(d.tasks.length, 3);
});

test("merge: newest edit wins, both sides' items are kept, deletions stick", () => {
  const shared = task("Original");
  const local = data([{ ...shared, title: "Phone edit", updatedAt: "2026-10-02T10:00:00Z" }, task("Phone only")]);
  const remote = data([{ ...shared, title: "Mac edit", updatedAt: "2026-10-02T09:00:00Z" }, task("Mac only"), task("Deleted on Mac")]);
  remote.deleted = { [remote.tasks[2].id]: S.iso() };
  local.tasks.push(remote.tasks[2]);
  const merged = S.merge(local, remote);
  assert.deepEqual(merged.tasks.map(t => t.title), ["Phone edit", "Phone only", "Mac only"]);
});

test("merge keeps fields this version doesn't know about", () => {
  const remote = data([task("From a newer Mac", { someNewField: { x: 1 } })]);
  const merged = S.merge(data(), remote);
  assert.deepEqual(merged.tasks[0].someNewField, { x: 1 });
});

test("dates are written without milliseconds, like the Mac", () => {
  assert.match(S.iso(new Date("2026-10-02T20:03:25.123Z")), /^2026-10-02T20:03:25Z$/);
});

test("commit summary matches the Mac's wording", () => {
  const before = data([task("Edit me"), task("Finish me"), task("Delete me")]);
  const after = JSON.parse(JSON.stringify(before));
  after.tasks[0].title = "Edited";
  after.tasks[1].completedAt = S.iso();
  after.tasks.splice(2, 1);
  after.tasks.push(task("New"));
  assert.equal(S.summary(before, after), "1 added, 1 completed, 1 edited, 1 deleted");
  assert.equal(S.summary(null, after), "3 added");
  assert.equal(S.summary(after, after), "settings changed");
});

test("reads setup links made by the Mac", () => {
  // Same encoding as SyncService.setupLink: sorted-key JSON, URL-safe base64 without padding.
  const json = JSON.stringify({ repo: "me/satori-data", token: "github_pat_abc+/=" });
  const code = Buffer.from(json).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  assert.deepEqual(S.parseSetupLink(`https://satorigtd.app/app/#connect=${code}`),
    { repo: "me/satori-data", token: "github_pat_abc+/=" });
  assert.equal(S.parseSetupLink("https://example.com"), null);
  assert.equal(S.parseSetupLink("#connect=not-base64-json"), null);
  const noRepo = Buffer.from(JSON.stringify({ repo: "nope", token: "x" })).toString("base64url");
  assert.equal(S.parseSetupLink("#connect=" + noRepo), null);
});

test("completing a project completes its open to-dos; reopening leaves them done", () => {
  const d = data();
  const p = S.addProject(d, "Kitchen shelves");
  S.addTask(d, "Measure the wall", "project:" + p.id);
  S.addTask(d, "Buy brackets", "project:" + p.id);
  S.completeProject(d, p.id);
  assert.ok(p.completedAt);
  assert.ok(d.tasks.every(t => t.completedAt));
  S.reopenProject(d, p.id);
  assert.equal(p.completedAt, undefined);
  assert.ok(d.tasks.every(t => t.completedAt));
});

test("finishing a project's last to-do is noticed", () => {
  const d = data();
  const p = S.addProject(d, "Kitchen shelves");
  const a = S.addTask(d, "Measure the wall", "project:" + p.id);
  const b = S.addTask(d, "Buy brackets", "project:" + p.id);
  S.complete(d, a.id);
  assert.equal(S.finishedProject(d, a), null, "one to-do is still open");
  S.complete(d, b.id);
  assert.equal(S.finishedProject(d, b), p);
  S.completeProject(d, p.id);
  assert.equal(S.finishedProject(d, b), null, "already complete");
});
