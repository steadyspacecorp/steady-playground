# Steady Check-ins (Tidbyt)

A [Tidbyt](https://tidbyt.com) app that shows today's [Steady](https://runsteady.com)
check-in status for a team as a grid of colored symbols.

![Preview](preview.png)

## What the symbols mean

| Symbol | Meaning |
| ------ | ------- |
| ⚪️ gray | No check-in yet today |
| 🔵 blue | Checked in |
| 🟢 green | Checked in and intentions met (`previous_completed`) |
| 🔴 red | Blocked (`blocked`) |

Shape encodes member type:

- **Circle** — person
- **Square** — agent

> The Steady v2 API doesn't yet expose a person-vs-agent type, so every member
> currently renders as a circle. The square path is wired up in `shape_for()` —
> switch on the type field there once the API provides it.

## How it works

On each render the app:

1. `GET /teams/{team_id}` to list the team's members.
2. `GET /check-ins?since=<today>&until=<today>&team_ids[]=<team_id>` to get
   today's check-ins, keyed by person.
3. Maps each member to a color (members with no check-in are yellow) and lays
   the symbols out in a grid sized to fit the 64×32 display.

"Today" is resolved in the device's timezone (`$tz`), falling back to
`America/New_York`.

Team membership is cached for 5 minutes; check-ins for 1 minute.

## Configuration

In the Tidbyt mobile app you set two things:

| Field | Description |
| ----- | ----------- |
| Personal access token | A Steady PAT (starts with `steady_pat_`), created in Steady settings. |
| Team | A dropdown of your teams **by name** — populated from `GET /teams` once the token is entered. The app stores the selected team's ID under the hood. |

## Develop

Requires [pixlet](https://github.com/tidbyt/pixlet).

```sh
# Live preview in the browser (gives you the same team picker)
pixlet serve steady_check_ins.star

# One-off render from the CLI — select the team by name or id
pixlet render steady_check_ins.star \
  pat=steady_pat_xxx team_name="Engineering" --magnify 8 -o preview.png

pixlet render steady_check_ins.star pat=steady_pat_xxx team_id=<uuid>
```

`team_name` matches case-insensitively. The dropdown in the mobile/serve UI
always sets `team_id`; `team_name` is a CLI convenience.

## Push to a device

A `push` sends one rendered frame; it doesn't auto-refresh. For a one-off:

```sh
pixlet render steady_check_ins.star pat=steady_pat_xxx team_name="Engineering"
pixlet push <device-id> steady_check_ins.webp \
  --api-token <tidbyt-api-token> \
  --url https://api.tidbyt.com \
  --installation-id steadycheckins
```

> Homebrew now installs the [Tronbyt fork](https://github.com/tronbyt/pixlet)
> of pixlet (Tidbyt's original was archived after the Modal acquisition). Two
> gotchas vs. the old pixlet: `push` has **no default URL**, so pass
> `--url https://api.tidbyt.com` (a stock Tidbyt still uses the Tidbyt cloud);
> and the installation ID must be **alphanumeric** — no hyphens. Run
> `pixlet config set url https://api.tidbyt.com` once to skip the flag locally.

## Keep it updated automatically

The repo includes a GitHub Action
([`.github/workflows/steady-check-ins.yml`](../.github/workflows/steady-check-ins.yml))
that renders and pushes every 30 minutes from GitHub's cloud — no machine of
your own stays on. Set these in the repo's **Settings → Secrets and variables →
Actions**:

| Kind | Name | Value |
| ---- | ---- | ----- |
| Secret | `STEADY_PAT` | Steady PAT (`steady_pat_…`); read-only scope is enough |
| Secret | `TIDBYT_API_TOKEN` | Tidbyt app → Settings → Get API Key |
| Secret | `TIDBYT_DEVICE_ID` | Tidbyt device ID (same screen) |
| Variable | `STEADY_TEAM_NAME` | Team to show (optional; defaults to `Data Science`) |

Secrets are safe in a public repo — they're encrypted, masked in logs, and not
exposed to fork pull requests. Trigger a first run from the **Actions** tab
(*Run workflow*) rather than waiting for the cron.
