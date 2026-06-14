<p align="center">
  <img src="https://raw.githubusercontent.com/ansxuman/Clauge/main/src-tauri/icons/128x128.png" alt="Clauge" width="84" />
</p>

<h1 align="center">Clauge for iOS</h1>

<p align="center"><strong>Your desktop coding sessions, in your pocket.</strong></p>

<p align="center">
  Companion app for <a href="https://clauge.in">Clauge</a> — attach to your Agent and SSH
  sessions from your iPhone, watch them live, and drive them with a tap.
</p>

<p align="center">
  <a href="https://clauge.in">Website</a> ·
  <a href="#build"><strong>Build from source →</strong></a> ·
  <a href="../../issues">Report a bug</a>
</p>

---

Pair your phone once, then open any running **Agent** (Claude · Codex · Gemini · OpenCode) or **SSH** session from your desktop Clauge and control it live — send prompts, approve actions, type into the terminal — over your local network or Tailscale. No relay; it talks straight to your machine.

## Features

- **Attach, don't re-spawn** — mirror the exact session running on your desktop
- **Every agent + SSH** — Claude, Codex, Gemini, OpenCode, and SSH terminals
- **Pair in seconds** — scan a QR from desktop **Settings → Mobile**
- **Get pinged** — push notifications when an agent needs your input

## Getting started

1. Desktop: **Settings → Mobile** → start the companion server → **Generate code**
2. App: scan the QR to pair, then open any session
3. Away from home? Reach your desktop over [Tailscale](https://clauge.in/docs.html#mobile)

## Build

Requires **Xcode 15+** on a Mac. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen     # if you don't have it
xcodegen generate         # regenerates Clauge.xcodeproj
open Clauge.xcodeproj
```

Then in Xcode:

1. Let Swift Package Manager resolve the **Firebase iOS SDK** on first open.
2. Select the **Clauge** target → Signing & Capabilities → set your **Team**.
3. For push, add your **`GoogleService-Info.plist`** to `Clauge/` and an **APNs auth key** in the Firebase console. The app builds and runs without it — push simply stays inert until you add it.

- Minimum iOS: **16.0**
- Bundle id: `com.clauge.mobile`

## Project layout

```
Clauge/
  Core/        Protocol (wire models), Net (REST + WebSocket), Store, Util
  Push/        Firebase Cloud Messaging + APNs
  UI/          Onboarding, Pair, Devices, Home, Terminal, Settings
  Resources/   term/ — the xterm.js terminal
```

The networking protocol — REST endpoints, the `replay/out/size/exit` WebSocket mirror, and QR pairing — matches the Clauge desktop companion server exactly.

## Built with

Swift · SwiftUI · xterm.js · WebKit · Firebase Cloud Messaging

## License

[PolyForm Noncommercial 1.0.0](LICENSE)
