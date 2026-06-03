# Steady Playground

A collection of client apps built on top of [Steady](https://runsteady.com)'s [API v2](https://runsteady.com/docs/api/category/getting-started/) and [MCP server](https://runsteady.com/docs/article/143-mcp-server/). Menu bar apps, activity sweepers, Tidbyt widgets, kiosks, whatever else fits.

These are toys, not products. They exist because Steady is headless -- it runs wherever you do -- and the easiest way to show that is to actually show it. Fork them, break them, build your own.

<img width="1364" height="797" alt="screen-and-tidbyt" src="https://github.com/user-attachments/assets/60987a97-e744-4bf3-9c47-c1e9b48942f4" />

## What's in here

Each app lives in its own top-level directory and stands on its own. No shared build system, no shared tooling. Pick one, read its README, run it.

| Directory | Form factor | Steady surface | What it does |
|---|---|---|---|
| [`claude-code-activity-summarizer/`](./claude-code-activity-summarizer) | Dockerized daemon | Webhooks | Summarizes your Claude Code sessions every few hours and posts the themes to Steady as activities. |
| [`macos-menu-digest-announcer/`](./macos-menu-digest-announcer) | macOS menu bar | API v2 | Click the icon, see (and hear) your latest digest entry. |
| [`macos-desktop-intentions/`](./macos-desktop-intentions) | macOS menu bar | API v2 | Display your intentions for the day right on your desktop. |
| [`tidbyt-check-ins/`](./tidbyt-check-ins) | Tidbyt (64×32 LED) | API v2 | A team's daily check-ins as a grid of colored dots — who's in, who met their intentions, who's blocked. |
| [`tidbyt-goal-stories/`](./tidbyt-goal-stories) | Tidbyt (64×32 LED) | API v2 | All visible top-level goals as stacked progress bars — color is status (off track/at risk/on track/complete), width is progress. |

More on the way: kiosks, mood boards, others as they come together.

## Build your own

The point of this repo is the next column of that table — yours. Start here:

- **API v2 docs:** https://runsteady.com/docs/api/category/getting-started/
- **MCP server docs:** https://runsteady.com/docs/article/143-mcp-server/
- **Webhook docs:** https://runsteady.com/docs/article/27-webhook/
- **Personal access tokens:** generate one from your [Steady connections page](https://app.steady.space/my/integrations/edit).

If you build something on Steady — useful, silly, weird, doesn't matter -- open a PR adding a row to the table, or just send us a link.

## Conventions

- One app per top-level directory.
- Each directory has its own README explaining what the app does, what Steady surface it uses, how to run it (or in the hardware cases, what you'd need to recreate it), and how to fork and modify.
- No secrets committed. Use `.env.example` or the equivalent for your stack, and document how to obtain an API key.
- Apps stay roughly as we wrote them — these are demos, not polished products.

## A note on hardware projects

Some of these will be reproducible (menu bar app, Claude Code activity summarizer). Some won't (you need a Tidbyt for the Tidbyt projects). For the hardware-bound ones, the README is honest about what you can run as-is vs. what's there as reference.

## Maintenance

Best effort. We'll take a look at issues and PRs when we can, but this repo isn't on a support rotation. If something's broken and blocks you, file an issue; if something's broken and you fix it, send a PR.

## License

MIT, applied across the whole repo. See [LICENSE](./LICENSE).
