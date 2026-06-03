# Claude Code Activity Summarizer

A daemon that periodically summarizes your Claude Code activity and posts it
to [Steady](https://runsteady.com) as activities via webhook.

Every `INTERVAL_HOURS` (default 6) it:

1. Finds Claude Code session transcripts (`~/.claude/projects`) modified since
   the last run
2. Builds a digest of session summaries and prompts, grouped by project
3. Asks `claude -p` to identify the distinct themes of work per project
4. Posts one Steady activity webhook per theme

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
