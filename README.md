# Stretch

A tiny native macOS menu-bar app that reminds you to take breaks — like
[Stretchly](https://hovancik.net/stretchly/), but built from scratch in Swift.

- **Short breaks** every 20 minutes (look away, rest your eyes) — 20s by default.
- **Long breaks** every 60 minutes (stand up, move) — 5 min by default.
- Breaks appear as a **dimmed full-screen overlay** on every display, with a
  countdown and **Skip** / **Postpone 5 min** buttons.
- Lives in the **menu bar** with a live countdown to the next break.
- No Dock icon, no Electron, ~2 MB, no runtime dependencies.

## Requirements

- macOS 13 (Ventura) or later
- Swift toolchain (`swift --version`) — the Command Line Tools are enough; full
  Xcode is not required.

## Build & run

```sh
./build.sh            # compiles and produces Stretch.app
open Stretch.app      # launches it (look for the icon in the menu bar)
```

To rebuild and relaunch during development:

```sh
./build.sh && killall Stretch 2>/dev/null; open Stretch.app
```

You can also run the raw binary without bundling (no app icon hiding):

```sh
swift run
```

## Menu

- **Take a short / long break now** — trigger a break immediately.
- **Reset timer** — restart the countdown to the next break.
- **Pause** — for 30 min, 1 hour, or indefinitely; **Resume** to continue.
- **Preferences…** — change intervals, durations, and launch-at-login.

## How scheduling works

A single 1-second timer drives a small state machine
(`working → breaking → working …`). Breaks occur every *short interval*; every
Nth break (where N = long interval ÷ short interval, default 3) is a long break.
Settings persist in `UserDefaults`.

## Project layout

```
Package.swift                 SwiftPM manifest (executable target)
Resources/Info.plist          Bundle metadata (LSUIElement = menu-bar app)
build.sh                      Compile + assemble Stretch.app + ad-hoc sign
Sources/Stretch/
  main.swift                  Entry point (.accessory activation policy)
  AppDelegate.swift           Wires scheduler ↔ menu ↔ overlay
  BreakScheduler.swift        The timing state machine
  MenuBarController.swift     Status item + menu + countdown label
  OverlayController.swift     Full-screen break overlay windows
  PreferencesController.swift Settings window
  Settings.swift              UserDefaults-backed preferences
```
