# Digest Announcer

A tiny macOS menu bar app that fetches your latest [Steady](https://runsteady.com) digest entry and reads it out loud when you click the icon.

https://github.com/user-attachments/assets/94bd18e4-3993-432f-aac2-952da67d3e36

## What it does

- Lives in the menu bar (no Dock icon).
- **Left-click** the icon → fetches the latest digest entry, shows it in a popover, and speaks it via macOS text-to-speech.
- **Right-click** (or ctrl-click) → menu: refresh, set token, toggle speech, quit.

## Requirements

- macOS 13+
- Swift toolchain (`swift --version`) — comes with Xcode or the Command Line Tools.
- A Steady **personal access token** (Read scope is enough). Generate one from your personal connections page on Steady.

## Build & install

```sh
./build.sh --install
```

That compiles a release binary, wraps it in `Digest Announcer.app`, copies it to `/Applications`, and opens it. To build without installing, just run `./build.sh` and the bundle lands at `.build/Digest Announcer.app`.

On first run macOS may complain about an unidentified developer (the build script ad-hoc signs it). Right-click → Open the first time to allow it.

## First-time setup

1. Click the menu bar icon (the newspaper). You'll see "No access token set."
2. Right-click the icon → **Set Token…**
3. Paste your Steady personal access token and hit Save.
4. Left-click the icon again — it should fetch and read your latest entry.

The token is stored in `UserDefaults` for this app's bundle ID. It's local to your user account but not encrypted; if you'd rather it lived in the keychain, swap out `TokenStore.swift`.

## Run on login

System Settings → **General** → **Login Items & Extensions** → **Open at Login** → click **+** → choose `/Applications/Digest Announcer.app`.

After that it'll start on every reboot and sit silently in your menu bar.

## API

Uses `GET https://service.steady.space/api/v2/digest?per_page=1` with `Authorization: Bearer <token>`. See [the Steady API docs](https://runsteady.com/docs/api/digest/) for the full schema.

## Project layout

```
Package.swift                # SwiftPM manifest (macOS 13+)
Sources/DigestAnnouncer/
  App.swift                  # AppDelegate, status item, popover wiring, TTS
  DigestClient.swift         # Steady API client + response model
  PopoverView.swift          # SwiftUI view inside the popover
  TokenStore.swift           # UserDefaults-backed token storage
Resources/Info.plist         # LSUIElement=true so it's menu-bar only
build.sh                     # Builds and bundles into a .app
```
