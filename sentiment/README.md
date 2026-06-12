# Steady Sentiment

The day's check-ins as a living aurora. Point it at a [Steady](https://runsteady.com) account, put it on a TV (or a browser tab), and the northern lights tell you how the team is doing: brighter and softer when the mood is up, dim and turbulent when it isn't, with a red shockwave every time someone's blocked. A readout strip along the bottom says what the score is and why.

The catch — and the point — is that nothing here is an LLM. The text is scored by two small transformer models running on-CPU in the server process. No API calls, no tokens leaving the box.

<img alt="Screenshot 2026-06-12 at 19 09 13" src="https://github.com/user-attachments/assets/8c367b79-c4bf-44f9-aaec-5309081acdd7" />

## What you're looking at

**The aurora.** A full-screen WebGL shader driven by a handful of smoothed values from the latest check-ins:

| Signal | Drives |
| ------ | ------ |
| Headline score (−1..1) | How bright, tall, and soft the curtains are — radiant days glow, stormy days dim |
| Energy (0..1) | Turbulence and speed — when fragments disagree, the field churns |
| Emotion mix | The palette — the top three emotions tint the light |
| Blocked count | A red shockwave that ripples across the sky every few seconds |

**The readout.** The headline score and its label (radiant / bright / steady / strained / stormy), chips for the dominant emotions, a pulsing chip when anyone's blocked, a plain-English "why" line, and the brightest and heaviest quotes of the day with attribution. The status bar lists the teams in scope, the models in use, and when the display last updated.

**Kiosk mode:** double-click anywhere to go fullscreen (double-click again or Esc to exit), or launch the browser chromeless yourself, e.g. `open -na "Google Chrome" --args --kiosk <url>` on macOS.

## How it works

A near-zero-dependency Node server (`node:http` + global `fetch`, plus one package for the models) does all the talking to Steady, so the personal access token never reaches the browser. Every `POLL_SECONDS` it:

1. Resolves the team scope: `STEADY_TEAM_IDS` if set, otherwise every team the token can see when `STEADY_SCOPE=all`, otherwise the token's own teams.
2. Fetches a `LOOKBACK_DAYS` window of check-ins, dedupes by id (a check-in can belong to several teams), and keeps the most recent day that actually has check-ins — so "today" before anyone has checked in falls back to yesterday's aurora instead of a blank sky.
3. Scores that day's check-ins (skipping the work when the inputs haven't changed since the last poll).
4. Pushes the rollup to every connected page over SSE (`/events`), where the shader eases toward the new weather rather than cutting to it.

### The scoring (no LLMs)

Each check-in's `previous`, `intentions`, and `blockers` markdown is stripped of code, links, and URLs and split into sentence-ish fragments. Every fragment is run through two models:

- **[`distilbert-base-uncased-finetuned-sst-2-english`](https://huggingface.co/Xenova/distilbert-base-uncased-finetuned-sst-2-english)** — binary positive/negative. This is the headline score.
- **[`roberta-base-go_emotions`](https://huggingface.co/SamLowe/roberta-base-go_emotions-onnx)** — 28 fine-grained emotions, folded into the seven Ekman buckets the aurora paints (joy, surprise, neutral, sadness, fear, anger, disgust). This is the palette.

Both run via [Transformers.js](https://huggingface.co/docs/transformers.js) on quantized ONNX weights — small enough to bake into the Docker image and fast enough to score a team's day in a few seconds on a CPU.

Fragments roll up into one team snapshot: blocker text counts double (more signal than a list of merged PRs), a blocked check-in takes a flat penalty on top of its prose, and "energy" is how much the fragments disagree with each other. The emotion distributions are blended into the mix that becomes the palette.

It's a vibe meter, not a diagnosis — small models miss sarcasm and read terse standup prose as `neutral` more often than a person would. Treat the aurora as a mood ring for the team, not a performance metric.

## Run it locally

Requires Node 22+ (or just Docker). The first boot downloads the model weights (~150MB) into `MODELS_DIR`; subsequent boots are instant.

```sh
cp .env.example .env   # add your PAT
npm install
npm run dev
# → http://localhost:3000
```

Or with Docker (weights are baked into the image at build time, so the container scores immediately):

```sh
docker build -t steady-sentiment .
docker run --rm -p 10000:10000 --env-file .env steady-sentiment
# → http://localhost:10000
```

## Configuration

| Env var | Default | Description |
| ------- | ------- | ----------- |
| `STEADY_PAT` | — | Steady PAT (`steady_pat_…`), created from your [connections page](https://app.steady.space/my/integrations/edit). Read-only scope is enough. |
| `STEADY_SCOPE` | `my` | `my` scores the token's own teams; `all` scores every team the token can see. |
| `STEADY_TEAM_IDS` | — | Comma-separated team UUIDs to score. Overrides `STEADY_SCOPE`. |
| `TZ` | system | Timezone used to resolve the check-in window. |
| `POLL_SECONDS` | `600` | How often the server polls Steady and re-scores. Each poll costs a handful of API requests against the PAT's 500-per-30-minute budget; scoring is skipped when nothing changed. |
| `LOOKBACK_DAYS` | `7` | How far back to look for the most recent day with check-ins. |
| `MODELS_DIR` | `./tmp/models` | Where model weights are cached. Docker overrides this to bake them into the image. |
| `PORT` | `3000` (`10000` in Docker) | Port to listen on. |

## Deploy on Render

[`render.yaml`](./render.yaml) is a ready-to-go [blueprint](https://render.com/docs/blueprint-spec) for a Docker web service. In Render: **New → Blueprint**, point it at this repo (your fork, or the public URL), and set **Blueprint Path** to `sentiment/render.yaml`. The only secret to set is `STEADY_PAT` — the blueprint marks it `sync: false` so Render prompts for it at deploy time. It's on the `standard` plan rather than `starter`: two transformer models in memory is tight under 512MB.

## Endpoints

| Path | What |
| ---- | ---- |
| `/` | The aurora page. |
| `/events` | SSE stream of scored snapshots. |
| `/api/sentiment` | Latest snapshot as plain JSON (handy for debugging). |
| `/up` | Health check. |
