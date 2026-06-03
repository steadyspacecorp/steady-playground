# Claude Code Activity Summarizer

A daemon that periodically summarizes your Claude Code activity and posts it
to [Steady](https://runsteady.com) as activities via webhook.

Every `INTERVAL_HOURS` (default 6) it:

1. Finds Claude Code session transcripts (`~/.claude/projects`) modified since
   the last run
2. Builds a digest of session summaries and prompts, grouped by project
3. Asks `claude -p` to identify the distinct themes of work per project
4. Posts one Steady activity webhook per theme, linking each to the project's
   GitHub repo (its `origin` remote) when it has one, else `SOURCE_URL` if set
   (disable repo links with `USE_GIT_ORIGIN_SOURCE_URL=false`)

<img width="800" height="451" alt="CleanShot 2026-06-03 at 15 32 26" src="https://github.com/user-attachments/assets/ef908bdd-776c-421b-86e6-786e2ecadae0" />

## Setup

1. Generate a long-lived token for headless Claude (uses your subscription):

   ```sh
   claude setup-token
   ```

2. Configure:

   ```sh
   cp .env.example .env
   # fill in CLAUDE_CODE_OAUTH_TOKEN, STEADY_WEBHOOK_URL, STEADY_EMAIL
   ```

3. Test it (dry run — summarizes the last `INTERVAL_HOURS` and prints the
   webhook payloads without posting anything):

   ```sh
   docker compose build
   docker compose run --rm summarizer test
   ```

4. Run the daemon:

   ```sh
   docker compose up -d
   ```

It summarizes immediately on start, then every `INTERVAL_HOURS`. Logs:

```sh
docker compose logs -f
```

Other one-off commands:

```sh
docker compose run --rm summarizer once   # single real run (posts + updates state)
```

## Repo links

Each activity's `source_url` points to the project's GitHub repo, resolved
from the repo's `origin` remote (transcripts record each session's working
directory, and the home directory is mounted read-only into the container so
the repo can be read). Projects without a GitHub origin fall back to
`SOURCE_URL`, or post no `source_url` at all if that's unset.

Set `USE_GIT_ORIGIN_SOURCE_URL=false` in `.env` to skip repo resolution and
always use `SOURCE_URL`.

## Scoping to specific projects

By default all projects in `~/.claude/projects` are summarized. To limit it,
set `PROJECT_DIRS` in `.env` to a comma-separated list of project paths:

```
PROJECT_DIRS=/Users/you/Developer/steady,/Users/you/Developer/side-project
```

## State

The last successful run timestamp is kept in `./data/last_run`, so restarts
don't re-post activity and failed runs are retried over the same window on the
next interval. Delete the file to re-summarize the last `INTERVAL_HOURS`.
