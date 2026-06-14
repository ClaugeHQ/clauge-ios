<div align="center">
  <img src="https://raw.githubusercontent.com/ansxuman/Clauge/main/src-tauri/icons/128x128.png" width="96" alt="Clauge" />
  <h1>Clauge for iOS</h1>
  <p>Drive your Clauge desktop coding sessions from your iPhone.</p>
</div>

Companion app for [Clauge](https://github.com/ansxuman/Clauge) — pair once, then attach to any running **Agent** (Claude · Codex · Gemini · OpenCode) or **SSH** session on your desktop and control it live over your local network or Tailscale. Mirrors the [Android app](https://github.com/ClaugeHQ/clauge-android).

- **Live terminal mirror** — watch output in real time, type, and approve actions (xterm.js in a `WKWebView`, phone-authoritative sizing).
- **QR pairing** — scan the code from desktop **Settings → Mobile**, or enter host/port/code by hand.
- **Push notifications** — get pinged when a session exits or an agent needs you (Firebase Cloud Messaging).
- **Multi-device** — pair several desktops and switch between them.

## Build

Requires **Xcode 15+** and a Mac. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen     # if you don't have it
xcodegen generate         # regenerates Clauge.xcodeproj
open Clauge.xcodeproj
```

Then in Xcode:

1. Let Swift Package Manager resolve the **Firebase iOS SDK** (first open).
2. Select the **Clauge** target → Signing & Capabilities → set your **Team**.
3. (Push) Drop your **`GoogleService-Info.plist`** into `Clauge/` and add an **APNs auth key** in the Firebase console. The app builds and runs without it — push simply stays inert (same as the Android `google-services.json` behaviour).

- Minimum iOS: **16.0**
- Bundle id: `com.clauge.mobile`

## Layout

```
Clauge/
  Core/        Protocol (wire models), Net (REST + WebSocket), Store, Util
  Push/        Firebase/APNs registration + AppDelegate
  UI/          Onboarding, Pair, Devices, Home, Terminal, Settings
  Resources/   term/ — the shared xterm.js terminal
```

The networking protocol (REST endpoints, the `replay/out/size/exit` WebSocket mirror, QR pairing) matches the Clauge desktop companion server exactly.
