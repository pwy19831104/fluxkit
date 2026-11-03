# StreamKit

A no-account, open-and-use iOS video downloader. Paste a link (or share one from Safari),
tap **Download**, keep the video offline. Built with SwiftUI, AVFoundation and URLSession —
zero third-party dependencies.

<p align="center">
  <img src="docs/screenshots/home.png" width="260" alt="Home screen">
</p>

## What it does

- **Paste → download.** Accepts direct media links (`mp4`, `mov`, `webm`, …) and HLS streams (`m3u8`).
- **Finds the media on a page.** If you paste a normal web page, the app scrapes
  `og:video`, `twitter:player:stream`, `<video>`, `<source>`, `<link rel="…" type="video/…">`
  and JSON-LD `contentUrl` candidates, then probes the winner's `Content-Type`.
- **HLS pipeline.** Master playlist → best variant → parallel segment download (6 at a time) →
  AES-128 segment decryption → fMP4 passthrough or MPEG-TS remux to `.mp4`. Separate audio
  renditions are muxed back with `AVMutableComposition`.
- **Downloads survive the app.** Progressive transfers run on a background `URLSession`, so they
  keep going while the app is suspended or terminated, and are re-matched after a relaunch via
  `taskDescription`. Pause/resume uses the system's resume data, so a paused transfer continues
  from the byte it stopped at.
- **Share sheet.** Share any link from Safari/YouTube-free sources straight into the app; the
  extension drops it into an App Group inbox and the app picks it up on next activation.
- **Play offline.** Built-in `AVPlayer`, share sheet, and *Save to Photos*.
- **Library.** Local JSON index in Application Support, thumbnails, size/duration, delete, retry.
- **Deep link.** `streamkit://open?url=<percent-encoded link>` lets Shortcuts or a
  share-sheet shortcut hand a URL over without retyping.

## Requirements

- Xcode 26 or newer, iOS 17+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the project file is generated
- An App Group named `group.com.streamkit.app` registered for both bundle ids when you build for a device

## Run it

```bash
xcodegen generate
open StreamKit.xcodeproj
```

Command line:

```bash
xcodebuild -project StreamKit.xcodeproj -scheme StreamKit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild test -project StreamKit.xcodeproj -scheme StreamKit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'
```

The project has two app targets: `StreamKit` (the app) and `StreamKitShare` (share
extension, embedded in `PlugIns/`).

## How a link is resolved

```
input ──► normalize (https://, validation)
          │
          ├─ HEAD / ranged GET probe ──► video/*, audio/*  ──► progressive download
          │                          └─ mpegurl / .m3u8 ──► HLS pipeline
          │
          └─ text/html ──► scrape candidates ──► probe ──► media
```

Downloads land in `Application Support/StreamKit/Media`, thumbnails next to them in
`…/Thumbnails`, pending resume data as `…/Media/<record-id>.resume`, and the index in
`…/library.json`.

## Lifecycle notes

- **Progressive downloads** use `URLSessionConfiguration.background(withIdentifier:)` with
  `sessionSendsLaunchEvents`. `AppDelegate` forwards
  `handleEventsForBackgroundURLSession` to `BackgroundSessionBridge`, and
  `urlSessionDidFinishEvents(forBackgroundURLSession:)` calls it back — otherwise iOS kills the
  app for stalling background work.
- **Relaunch reconciliation:** `DownloadManager.reconcileWithSystem()` asks the system for live
  tasks and marks anything still "running" in the index as paused (resume data present) or
  interrupted (no data). Task identity travels in `taskDescription` (`<uuid>|<ext>`), because
  `taskIdentifier`s are not stable across launches.
- **HLS downloads** are orchestrated in-process (parallel segments + remux), so they pause when
  the app is suspended. Resume data doesn't apply to them.

## Layout

```
Sources/
  App/        entry point + app delegate (background session events)
  Core/       models + on-disk paths
  Services/   LinkResolver, DownloadManager, HLSDownloader, LibraryStore, thumbnails, Photos
  Views/      Home, Downloads, Library, Player, preview sheet, theme
  Debug/      DEBUG-only smoke test harness
Shared/       SharedInbox (App Group mailbox, compiled into app + extension)
ShareExtension/
              ShareViewController (share sheet UI + link extraction)
Tests/        resolver, model, HLS and deep-link unit tests
project.yml   XcodeGen spec (Info.plists + entitlements are generated from it)
```

## Debug hooks (DEBUG builds only)

```bash
# Resolve + download a list of links, logging outcomes to the unified log
SIMCTL_CHILD_SMOKE_URLS="https://example.com/a.mp4" \
  xcrun simctl launch --console booted com.streamkit.app --smoke-test

# Same, but pause after 3 s and resume 1.5 s later (exercises resume data)
SIMCTL_CHILD_SMOKE_PAUSE=1 SIMCTL_CHILD_SMOKE_URLS="…" \
  xcrun simctl launch booted com.streamkit.app --smoke-test

# Simulate the share extension writing into the App Group
SIMCTL_CHILD_INBOX_PUSH="https://example.com/page" xcrun simctl launch booted com.streamkit.app

# Pre-fill the field and open the preview sheet / start on a tab
SIMCTL_CHILD_PREVIEW_URL="…" SIMCTL_CHILD_SHOW_TAB=library xcrun simctl launch booted com.streamkit.app
```

## Scope and limitations

- **Platform lock-in is deliberate.** YouTube, TikTok, Instagram and similar services sign
  their media URLs and protect them with DRM; downloading them requires a server-side
  extractor and violates their terms. This app only handles links it can resolve over plain
  HTTP, and it never bypasses DRM or paywalls.
- **Simulator quirk:** `AVAssetExportSession` fails on the simulator (`AVFoundationErrorDomain -11800`).
  The concatenated stream is still saved (`.mp4` for fMP4, `.ts` for legacy TS) and the app
  falls back gracefully; verify remuxing on a physical device.
- Subtitle renditions are ignored; audio is muxed from the default rendition only.
- The share extension can't launch the app itself in most iOS versions; it saves the link and
  shows "Open StreamKit", which drains the inbox on activation.

## Before shipping to the App Store

- Replace `com.streamkit.app` / `com.streamkit.app.share` with your own ids, set a
  development team, and register `group.com.streamkit.app` in the developer portal for both.
- App icon lives in `Sources/Resources/Assets.xcassets/AppIcon.appiconset` — regenerate with your brand.
- `NSAllowsArbitraryLoads` is enabled because users can supply `http://` media. Explain this in
  App Review notes; alternatively restrict to `NSAllowsArbitraryLoadsForMedia`.
- Guideline 5.2.3 (copyright) is the main rejection risk for downloader apps: keep the in-app
  notice ("only download content you have permission to save"), avoid naming third-party
  platforms in the metadata, and be ready to explain the DRM stance.
- Privacy: no analytics, no accounts, no network calls except the URLs the user provides.
