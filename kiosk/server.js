// Steady Kiosk -- a one-page wall display for a Steady account.
//
// Left side:  today's check-in status per team member, one shape each.
//             Circles are humans, squares are agents (Person#kind).
// Right side: goals as horizontal progress bars, subgoals indented under
//             their parents. Width is the latest update's progress; color
//             is its confidence.
//
// The browser never sees the Steady PAT. This server polls the v2 REST API
// (https://service.steady.space/api/v2) every POLL_SECONDS and pushes the
// aggregated snapshot to connected pages over server-sent events, so the
// display updates in place without reloading.
//
// Zero dependencies -- node:http and global fetch only.

import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const API_BASE = "https://service.steady.space/api/v2";
const PORT = Number(process.env.PORT || 3000);
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 300);
const PAT = (process.env.STEADY_PAT || "").trim();
const SCOPE = (process.env.STEADY_SCOPE || "my").trim().toLowerCase(); // "my" | "all"
const TEAM_IDS = (process.env.STEADY_TEAM_IDS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const PER_PAGE = 50;
const MAX_PAGES = 20;

const PUBLIC_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "public");
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
};

let snapshot = null; // last good payload
let lastError = PAT ? null : "STEADY_PAT is not set";
const clients = new Set(); // open SSE responses

// --- Steady API ---------------------------------------------------------

async function apiGet(apiPath, params = {}, attempt = 1) {
  const url = new URL(API_BASE + apiPath);
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) value.forEach((v) => url.searchParams.append(key, v));
    else url.searchParams.set(key, value);
  }
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${PAT}`, Accept: "application/json" },
  });
  if (response.status === 429 && attempt <= 3) {
    // Honor Retry-After for brief throttles, but don't sleep out a long
    // rate-limit window -- fail the poll and surface the error instead.
    const seconds = Math.min(Number(response.headers.get("retry-after")) || 2 ** attempt, 15);
    await new Promise((resolve) => setTimeout(resolve, seconds * 1000));
    return apiGet(apiPath, params, attempt + 1);
  }
  if (!response.ok) throw new Error(`Steady API ${response.status} on GET ${apiPath}`);
  return response.json();
}

// Run fn over items with at most `limit` requests in flight, preserving order.
async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const index = next++;
        results[index] = await fn(items[index]);
      }
    }),
  );
  return results;
}

async function getAll(apiPath, params = {}) {
  const all = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const batch = await apiGet(apiPath, { ...params, page, per_page: PER_PAGE });
    all.push(...batch);
    if (batch.length < PER_PAGE) break;
  }
  return all;
}

// --- snapshot -----------------------------------------------------------

// "Today" in the kiosk's timezone; Node resolves Date against the TZ env var.
const todayISO = () => new Date().toLocaleDateString("en-CA");

function initials(name) {
  const words = (name || "").trim().split(/\s+/).filter(Boolean);
  if (!words.length) return "?";
  return (words[0][0] + (words.length > 1 ? words.at(-1)[0] : "")).toUpperCase();
}

// gray: no check-in yet | blue: checked in | green: intentions met | red: blocked
function checkInStatus(checkIn) {
  if (!checkIn || checkIn.absent) return "pending";
  if (checkIn.blocked) return "blocked";
  if (checkIn.previous_completed === true) return "done";
  return "checked_in";
}

// Map a goal's latest update to [status, progress]. Progress 100 always
// reads complete, regardless of confidence.
function goalStatus(update) {
  if (!update) return ["no_update", 0];
  const progress = Number(update.progress) || 0;
  if (progress >= 100) return ["complete", 100];
  switch ((update.confidence_description || "").toLowerCase()) {
    case "off track": return ["off_track", progress];
    case "at risk": return ["at_risk", progress];
    case "on track": return ["on_track", progress];
    default: return ["no_update", progress];
  }
}

// Scope: explicit STEADY_TEAM_IDS wins, then STEADY_SCOPE=all (every team
// the token can see), then the default of the token's own teams.
async function resolveTeams() {
  if (TEAM_IDS.length) {
    return (await getAll("/teams")).filter((t) => TEAM_IDS.includes(t.id));
  }
  if (SCOPE === "all") return getAll("/teams");
  return (await apiGet("/me")).teams;
}

async function buildSnapshot() {
  const teams = await resolveTeams();
  const teamIds = teams.map((t) => t.id);
  if (!teamIds.length) throw new Error("No teams visible to this token");

  const today = todayISO();
  const [allPeople, checkIns, allGoals] = await Promise.all([
    getAll("/people"),
    getAll("/check-ins", { since: today, until: today, "team_ids[]": teamIds }),
    getAll("/goals", { "team_ids[]": teamIds }),
  ]);

  const checkInsByPerson = new Map(checkIns.map((c) => [c.person.id, c]));
  const people = allPeople
    .filter((p) => (p.teams || []).some((t) => teamIds.includes(t.id)))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((p) => ({
      id: p.id,
      name: p.name,
      initials: initials(p.name),
      kind: p.kind === "agent" ? "agent" : "human",
      status: checkInStatus(checkInsByPerson.get(p.id)),
      mood: checkInsByPerson.get(p.id)?.mood || null,
    }));

  const goals = await mapLimit(orderGoals(allGoals), 4, async ({ goal, depth }) => {
    const [update] = await apiGet(`/goals/${goal.id}/goal-updates`, { per_page: 1 });
    const [status, progress] = goalStatus(update);
    return { id: goal.id, title: goal.title, progress, status, depth };
  });

  return {
    people,
    goals,
    teams: teams.map((t) => t.name).sort((a, b) => a.localeCompare(b)),
    date: today,
    updated_at: new Date().toISOString(),
  };
}

// Depth-first goal ordering: top-level goals first (end_date ASC with missing
// last, then title -- matching the web UI), each followed by its subgoals,
// recursively. Goals whose parent isn't visible to this token render as roots.
function orderGoals(allGoals) {
  const ids = new Set(allGoals.map((g) => g.id));
  const childrenOf = new Map();
  const roots = [];
  for (const goal of allGoals) {
    const parentId = goal.parent?.id;
    if (parentId && ids.has(parentId)) {
      if (!childrenOf.has(parentId)) childrenOf.set(parentId, []);
      childrenOf.get(parentId).push(goal);
    } else {
      roots.push(goal);
    }
  }

  const byPlan = (a, b) =>
    (a.end_date || "9999-12-31").localeCompare(b.end_date || "9999-12-31") ||
    (a.title || "").localeCompare(b.title || "");

  const ordered = [];
  const visit = (goal, depth) => {
    ordered.push({ goal, depth });
    (childrenOf.get(goal.id) || []).sort(byPlan).forEach((child) => visit(child, depth + 1));
  };
  roots.sort(byPlan).forEach((root) => visit(root, 0));
  return ordered;
}

// --- polling & SSE ------------------------------------------------------

function payload() {
  return JSON.stringify({ ...(snapshot || { people: [], goals: [] }), error: lastError });
}

let polling = false;

async function poll() {
  if (!PAT || polling) return;
  polling = true;
  try {
    snapshot = await buildSnapshot();
    lastError = null;
  } catch (err) {
    lastError = err.message;
  } finally {
    polling = false;
  }
  const data = `data: ${payload()}\n\n`;
  for (const res of clients) res.write(data);
}

poll();
setInterval(poll, POLL_SECONDS * 1000);
setInterval(() => {
  for (const res of clients) res.write(": heartbeat\n\n");
}, 25_000);

// --- http ---------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, "http://localhost");

  if (pathname === "/up") return res.end("OK");

  if (pathname === "/api/kiosk") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(payload());
  }

  if (pathname === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(`data: ${payload()}\n\n`);
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }

  // Static files from public/.
  const file = path.join(PUBLIC_DIR, pathname === "/" ? "index.html" : pathname);
  if (!file.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    return res.end();
  }
  try {
    let body = await readFile(file);
    if (file.endsWith("index.html")) {
      // Absolute URLs for the Open Graph tags, whatever host we're behind.
      const proto = req.headers["x-forwarded-proto"] || "http";
      body = body.toString().replaceAll("__BASE_URL__", `${proto}://${req.headers.host}`);
    }
    res.writeHead(200, {
      "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
      // Always revalidate so a fresh deploy isn't paired with stale assets.
      "Cache-Control": "no-cache",
    });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
});

server.listen(PORT, () => console.log(`Steady Kiosk listening on :${PORT}`));
