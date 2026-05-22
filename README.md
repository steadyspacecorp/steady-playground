# Steady Playground

A collection of client apps built on top of [Steady](https://runsteady.com)'s [API v2](https://runsteady.com/docs/api/) and [MCP server](https://runsteady.com/docs/mcp/). Menu bar apps, Tidbyt widgets, a rotary phone, whatever else fits.

These are toys, not products. They exist because Steady is headless -- it runs wherever you do -- and the easiest way to show that is to actually show it. Fork them, break them, build your own.

## What's in here

Each app lives in its own top-level directory and stands on its own. No shared build system, no shared tooling. Pick one, read its README, run it.

| Directory | Form factor | Steady surface | What it does |
|---|---|---|---|
| [`macos-menu-digest-announcer/`](./macos-menu-digest-announcer) | macOS menu bar | API v2 | Click the icon, see — and hear — your latest digest entry. |

More on the way: Tidbyt, vintage phone, others as they come together.

## Build your own

The point of this repo is the next column of that table — yours. Start here:

- **API v2 docs:** https://runsteady.com/docs/api/
- **MCP server docs:** https://runsteady.com/docs/mcp/
- **Personal access tokens:** generate one from your Steady connections page.

If you build something on Steady — useful, silly, weird, doesn't matter — open a PR adding a row to the table, or just send us a link.

## Conventions

- One app per top-level directory.
- Each directory has its own README explaining what the app does, what Steady surface it uses, how to run it (or in the hardware cases, what you'd need to recreate it), and how to fork and modify.
- No secrets committed. Use `.env.example` or the equivalent for your stack, and document how to obtain an API key.
- Apps stay roughly as we wrote them — these are demos, not polished products.

## A note on hardware projects

Some of these will be reproducible (menu bar app, Tidbyt). Some won't (the vintage phone project involves a specific physical device). For the hardware-bound ones, the README is honest about what you can run as-is vs. what's there as reference.

## Maintenance

Best effort. We'll take a look at issues and PRs when we can, but this repo isn't on a support rotation. If something's broken and blocks you, file an issue; if something's broken and you fix it, send a PR.

## License

MIT, applied across the whole repo. See [LICENSE](./LICENSE).
