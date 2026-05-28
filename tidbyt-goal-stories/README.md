# Steady Goal Stories (Tidbyt)

A [Tidbyt](https://tidbyt.com) app that shows every top-level
[Steady](https://runsteady.com) goal you can see as a stack of horizontal
progress bars.

![Preview](preview.png)

## What the bars mean

| Color | Status |
| ----- | ------ |
| 🔴 red | Off track (confidence 30) |
| 🟠 orange | At risk (confidence 60) |
| 🔵 blue | On track (confidence 90) |
| 🟢 green | Complete (progress 100) |
| ⚫ gray | No update yet |

**Bar width** is the goal's latest `progress` percent. Width is over the dim
track; the colored portion is how far the goal has gone.

Only **top-level** goals (those with no parent) are shown — these are the
rollups the contributing goals feed into. Bars auto-size so the stack stays
centered whether you have 1 goal or 12.

## How it works

On each render the app:

1. `GET /goals` to list every goal the token can see.
2. Keeps only goals where `parent` is null.
3. For each, `GET /goals/<id>/goal-updates?per_page=1` to fetch the latest
   update — that's where `progress` and `confidence_description` come from.
4. Lays the bars out vertically with auto-tuned heights.

Goals and their updates change daily, not minute-by-minute, so each response
is cached for 5 minutes.

## Configuration

In the Tidbyt mobile app you set one thing:

| Field | Description |
| ----- | ----------- |
| Personal access token | A Steady PAT (starts with `steady_pat_`), created in Steady settings. |

The token's visibility determines which goals appear — there's no team
filter.

## Develop

Requires [pixlet](https://github.com/tidbyt/pixlet).

```sh
# Live preview in the browser
pixlet serve steady_goals.star

# One-off render from the CLI
pixlet render steady_goals.star pat=steady_pat_xxx --magnify 8 -o preview.png
```

## Push to a device

A `push` sends one rendered frame; it doesn't auto-refresh. For a one-off:

```sh
pixlet render steady_goals.star pat=steady_pat_xxx -o /tmp/goals.webp
pixlet push <device-id> /tmp/goals.webp \
  --api-token <tidbyt-api-token> \
  --url https://api.tidbyt.com \
  --installation-id steadygoalstories
```

> Homebrew now installs the [Tronbyt fork](https://github.com/tronbyt/pixlet)
> of pixlet (Tidbyt's original was archived after the Modal acquisition). Two
> gotchas vs. the old pixlet: `push` has **no default URL**, so pass
> `--url https://api.tidbyt.com` (a stock Tidbyt still uses the Tidbyt cloud);
> and the installation ID must be **alphanumeric** — no hyphens. Run
> `pixlet config set url https://api.tidbyt.com` once to skip the flag locally.

## Keep it updated automatically

The repo includes a GitHub Action
([`.github/workflows/steady-goal-stories.yml`](../.github/workflows/steady-goal-stories.yml))
that renders and pushes every 30 minutes from GitHub's cloud — no machine of
your own stays on. Set these in the repo's **Settings → Secrets and variables →
Actions**:

| Kind | Name | Value |
| ---- | ---- | ----- |
| Secret | `STEADY_PAT` | Steady PAT (`steady_pat_…`); read-only scope is enough |
| Secret | `TIDBYT_API_TOKEN` | Tidbyt app → Settings → Get API Key |
| Secret | `TIDBYT_DEVICE_ID` | Tidbyt device ID (same screen) |

Secrets are safe in a public repo — they're encrypted, masked in logs, and not
exposed to fork pull requests. Trigger a first run from the **Actions** tab
(*Run workflow*) rather than waiting for the cron.
