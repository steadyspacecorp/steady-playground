// Steady Sentiment -- the day's check-ins as a living aurora.
//
// The server pulls the latest check-ins from the Steady v2 REST API and
// scores their text with two small transformer models (see models.js --
// no LLMs, everything runs on-CPU in this process). The rollup -- one
// headline score, an energy level, an emotion mix, who's blocked -- is
// pushed to connected pages over server-sent events, where a WebGL shader
// turns it into northern lights: palette from the emotions, turbulence
// from the disagreement, red pulses for blockers.
//
// The browser never sees the Steady PAT. One dependency
// (@huggingface/transformers); the rest is node:http and global fetch.

import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { scoreCheckIns, loadModels, SENTIMENT_MODEL, EMOTION_MODEL } from "./models.js";

const API_BASE = "https://service.steady.space/api/v2";
const PORT = Number(process.env.PORT || 3000);
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 600);
const LOOKBACK_DAYS = Number(process.env.LOOKBACK_DAYS || 7);
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
let lastError = PAT ? "Warming up the models…" : "STEADY_PAT is not set";
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

// Dates resolve in the server's timezone; Node reads the TZ env var.
const isoDate = (date) => date.toLocaleDateString("en-CA");

// Scope: explicit STEADY_TEAM_IDS wins, then STEADY_SCOPE=all (every team
// the token can see), then the default of the token's own teams.
async function resolveTeams() {
  if (TEAM_IDS.length) {
    return (await getAll("/teams")).filter((t) => TEAM_IDS.includes(t.id));
  }
  if (SCOPE === "all") return getAll("/teams");
  return (await apiGet("/me")).teams;
}

// Scoring is the expensive part of a poll, so skip it when the inputs
// haven't changed -- the usual case on a quiet afternoon.
let scored = { key: null, value: null };

async function buildSnapshot() {
  const teams = await resolveTeams();
  const teamIds = teams.map((t) => t.id);
  if (!teamIds.length) throw new Error("No teams visible to this token");

  const until = new Date();
  const since = new Date(until);
  since.setDate(since.getDate() - (LOOKBACK_DAYS - 1));

  // One window-sized fetch, then keep the most recent day that actually
  // has check-ins -- "today" before anyone has checked in falls back to
  // yesterday's aurora instead of a blank sky. A check-in can belong to
  // several teams and show up once per team, so dedupe by id.
  const window = await getAll("/check-ins", {
    since: isoDate(since),
    until: isoDate(until),
    "team_ids[]": teamIds,
  });
  const byId = new Map(window.filter((c) => !c.absent).map((c) => [c.id, c]));
  const date = [...byId.values()].map((c) => c.date).sort().at(-1) || isoDate(until);
  const checkIns = [...byId.values()].filter((c) => c.date === date);

  const key = checkIns.map((c) => `${c.id}:${c.updated_at}`).sort().join("|");
  if (key !== scored.key) scored = { key, value: await scoreCheckIns(checkIns) };

  return {
    ...scored.value,
    date,
    teams: teams.map((t) => t.name).sort((a, b) => a.localeCompare(b)),
    models: { sentiment: SENTIMENT_MODEL, emotion: EMOTION_MODEL },
    updated_at: new Date().toISOString(),
  };
}

// --- polling & SSE ------------------------------------------------------

function payload() {
  return JSON.stringify({ ...(snapshot || {}), error: lastError });
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

// Pull the model weights (cached after the first boot) before the first
// poll so a cold start shows "warming up" instead of a long silent stall.
loadModels().then(poll, (err) => (lastError = err.message));
setInterval(poll, POLL_SECONDS * 1000);
setInterval(() => {
  for (const res of clients) res.write(": heartbeat\n\n");
}, 25_000);

// --- http ---------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, "http://localhost");

  if (pathname === "/up") return res.end("OK");

  if (pathname === "/api/sentiment") {
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

server.listen(PORT, () => console.log(`Steady Sentiment listening on :${PORT}`));
