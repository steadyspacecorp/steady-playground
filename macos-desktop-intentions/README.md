# Steady Intentions

A tiny macOS menu bar app that floats today's [Steady](https://runsteady.com)
check-in intentions on your desktop, anchored to a corner of your screen like
part of your wallpaper.

https://github.com/user-attachments/assets/c3b50596-6928-45c6-8df5-f1c834ef0e05

## What it does

- Lives in the menu bar (no Dock icon).
- Renders today's intentions exactly as you wrote them — bullets stay
  bullets, paragraphs stay paragraphs — with markdown inline formatting
  (bold, italics, code, links) preserved.
- The window sits at the **desktop layer** (below all app windows) and is
  **click-through** — it never gets in the way and never raises itself above
  other windows. Any fullscreen app naturally covers it.
- Cheap polling — refreshes every 3 minutes using the response `ETag`, so
  unchanged days come back as a free `304`.
- Menu bar lets you change **Position**, **Text Size**, and **Text Color**,
  and the choices persist across launches.

## Requirements

- macOS 14+
- Swift toolchain (`swift --version`) — comes with Xcode or the Command Line
  Tools.
- A Steady **personal access token** (Read scope is enough). Generate one
  from your personal connections page on Steady.

## Build & install

```sh
./build-app.sh
open "build/Steady Intentions.app"
```

To install it permanently, drag `build/Steady Intentions.app` into
`/Applications`. On first run macOS may complain about an unidentified
developer (the build script ad-hoc signs it). Right-click → **Open** the first
time to allow it.

## First-time setup

1. Open the app. You'll see "Set your Steady token from the menu bar to begin."
2. Click the menu bar icon → **Set Token…**
3. Paste your Steady personal access token (it starts with `steady_pat_`) and
   hit Save.
4. The card refreshes immediately and then every few minutes.

The token is stored in your **macOS Keychain** (service
`space.steady.intentions`), not on disk in plaintext.

## Menu bar

- **Show / Hide** — toggle the desktop card.
- **Refresh Now** (⌘R) — force a fresh fetch, bypassing the ETag cache.
- **Position ▸** — Top Left / Top Right / Bottom Left / Bottom Right.
- **Text Size ▸** — Small / Medium / Large / Extra Large. Window width scales
  with text size so the line wrap stays consistent.
- **Text Color…** — opens the macOS color picker; defaults to white.
- **Set Token…** — replace your stored Steady PAT.
- **Quit Steady Intentions** (⌘Q).

## Run on login

System Settings → **General** → **Login Items & Extensions** → **Open at
Login** → click **+** → choose `/Applications/Steady Intentions.app`.

After that it'll start on every reboot and sit silently as part of your
wallpaper.

## API

Uses two v2 REST endpoints with `Authorization: Bearer <token>`:

- `GET https://service.steady.space/api/v2/me` — to look up your person id.
- `GET https://service.steady.space/api/v2/check-ins?people_ids[]=<you>&since=<today>&until=<today>&per_page=1`
  — to get today's check-in.

See [the Steady API docs](https://app.steady.space/openapi.yml) for the full
schema. One inaccuracy worth knowing: `/me`'s `bio` is documented as plain
text but is actually returned as HTML.

## Project layout

```
Package.swift                # SwiftPM manifest (macOS 14+)
Sources/SteadyIntentions/
  main.swift                 # AppDelegate, status item, polling loop, token entry
  DesktopWindow.swift        # Desktop-level click-through panel
  IntentionsView.swift       # SwiftUI card + lightweight markdown rendering
  SteadyClient.swift         # API models + ETag-aware polling client
  Keychain.swift             # Token storage in the Keychain
  ColorStore.swift           # Persists the chosen text color
  CornerStore.swift          # Persists the chosen screen corner
  TextSizeStore.swift        # Persists the chosen text size
Resources/
  AppIcon.png                # 1024×1024 source for the .icns app icon
  MenuBarIcon.svg            # template image used in the menu bar
build-app.sh                 # Compiles, bundles, generates the icon, ad-hoc signs
```
