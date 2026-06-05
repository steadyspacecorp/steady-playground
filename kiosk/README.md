# Steady Kiosk

A one-page wall display for a [Steady](https://runsteady.com) account. Put it on a TV in the office (or a browser tab) and watch the day happen: who's checked in on the left, how the goals are tracking on the right. It updates in place — no reloads — over server-sent events.

## What you're looking at

**Left — check-ins.** One shape per team member, initials inside, sized so the grid fills the panel. Circles are humans, squares are agents (`Person#kind` from the v2 API) — agents wear a 🤖 badge on the top-right corner. If a human's check-in includes a mood, its emoji sits in the same spot, using Steady's canonical mood set. Status as color:

| Color | Meaning |
| ----- | ------- |
| ⚪️ gray | No check-in yet today |
| 🔵 blue | Checked in |
| 🟢 green | Checked in and intentions met (`previous_completed`) |
| 🔴 red | Blocked (`blocked`) — pulses |

**Right — goal stories.** Goals as horizontal bars sharing the panel height, with subgoals indented under their parents. Width is the latest update's `progress`; color is its `confidence_description`:

| Color | Meaning |
| ----- | ------- |
| 🔴 red | Off track |
| 🟠 orange | At risk |
| 🔵 blue | On track |
| 🟢 green | Complete (progress 100) |
| ⚪️ gray | No update yet |

The layout is responsive: side-by-side panels on a wide screen, stacked on a narrow one, with type and shapes scaling to the display. The status bar lists the teams in scope and when the display last updated.

**Kiosk mode:** double-click anywhere on the page to go fullscreen (double-click again or Esc to exit). Or launch the browser chromeless yourself, e.g. `open -na "Google Chrome" --args --kiosk <url>` on macOS.

## How it works

A zero-dependency Node server (`node:http` + global `fetch`, nothing to install) does all the talking to Steady, so the personal access token never reaches the browser. Every `POLL_SECONDS` it:

1. Resolves the team scope: `STEADY_TEAM_IDS` if set, otherwise `GET /teams` (every team the token can see) when `STEADY_SCOPE=all`, otherwise `GET /me` for the token's own teams.
2. `GET /people` and keeps members of those teams — this is where `kind: human | agent` comes from.
3. `GET /check-ins?since=<today>&until=<today>&team_ids[]=…` to color the shapes (and pick up moods). "Today" resolves in the `TZ` env var's zone.
4. `GET /goals?team_ids[]=…`, orders them depth-first (top-level goals with their subgoals nested under them), and grabs each one's latest update for progress + confidence. Goals whose parent isn't visible to the token render as top-level.

The aggregated snapshot is pushed to every connected page over SSE (`/events`). The page updates elements in place, so status changes fade and bars slide to their new width rather than redrawing.

## Run it locally

Requires Node 22+ (or just Docker).

```sh
cp .env.example .env   # add your PAT
npm run dev
# → http://localhost:3000
```

Or with Docker:

```sh
docker build -t steady-kiosk .
docker run --rm -p 10000:10000 --env-file .env steady-kiosk
# → http://localhost:10000
```

## Configuration

| Env var | Default | Description |
| ------- | ------- | ----------- |
| `STEADY_PAT` | — | Steady PAT (`steady_pat_…`), created from your [connections page](https://app.steady.space/my/integrations/edit). Read-only scope is enough. |
| `STEADY_SCOPE` | `my` | `my` shows the token's own teams; `all` shows every team the token can see. Applies to both check-ins and goals. |
| `STEADY_TEAM_IDS` | — | Comma-separated team UUIDs to display. Overrides `STEADY_SCOPE`. |
| `TZ` | system | Timezone used to resolve "today" for check-ins. |
| `POLL_SECONDS` | `30` | How often the server polls Steady and pushes to pages. |
| `PORT` | `3000` (`10000` in Docker) | Port to listen on. |

## Deploy on Render

[`render.yaml`](./render.yaml) is a ready-to-go [blueprint](https://render.com/docs/blueprint-spec) for a Docker web service. In Render: **New → Blueprint**, point it at this repo (your fork, or the public URL), and set **Blueprint Path** to `kiosk/render.yaml`. The only secret to set is `STEADY_PAT` — the blueprint marks it `sync: false` so Render prompts for it at deploy time.

Prefer skipping the blueprint? Create a plain web service pointed at this repo with **Root Directory** set to `kiosk` and set the env vars from the table above yourself.

## Endpoints

| Path | What |
| ---- | ---- |
| `/` | The kiosk page. |
| `/events` | SSE stream of display snapshots. |
| `/api/kiosk` | Latest snapshot as plain JSON (handy for debugging). |
| `/up` | Health check. |
