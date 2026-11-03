# DownloadKit

A no-account, open-and-use iOS video downloader. Paste a link, tap **Download**, keep the
video offline. Built with SwiftUI, AVFoundation and URLSession — zero third-party dependencies.

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
- **Play offline.** Built-in `AVPlayer`, share sheet, and *Save to Photos*.
- **Library.** Local JSON index in Application Support, thumbnails, size/duration, delete, retry.
- **Deep link.** `downloadkit://open?url=<percent-encoded link>` lets Shortcuts or a
  share-sheet shortcut hand a URL over without retyping.

## Requirements

- Xcode 26 or newer, iOS 17+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the project file is generated

## Run it

```bash
xcodegen generate
open DownloadKit.xcodeproj
```

Command line:

```bash
xcodebuild -project DownloadKit.xcodeproj -scheme DownloadKit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild test -project DownloadKit.xcodeproj -scheme DownloadKit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'
```

## How a link is resolved

```
input ──► normalize (https://, validation)
          │
          ├─ HEAD / ranged GET probe ──► video/*, audio/*  ──► progressive download
          │                          └─ mpegurl / .m3u8 ──► HLS pipeline
          │
          └─ text/html ──► scrape candidates ──► probe ──► media
```

Downloads land in `Application Support/DownloadKit/Media`, thumbnails next to them in
`…/Thumbnails`, and the index in `…/library.json`.

## Layout

```
Sources/
  App/        entry point
  Core/       models + on-disk paths
  Services/   LinkResolver, DownloadManager, HLSDownloader, LibraryStore, thumbnails, Photos
  Views/      Home, Downloads, Library, Player, preview sheet, theme
  Debug/      DEBUG-only smoke test harness
Tests/        resolver, model, HLS and deep-link unit tests
project.yml   XcodeGen spec (Info.plist is generated from it)
```

## Debug hooks (DEBUG builds only)

```bash
# Resolve + download a list of links, logging outcomes to the unified log
SIMCTL_CHILD_SMOKE_URLS="https://example.com/a.mp4" \
  xcrun simctl launch --console booted com.downloadkit.app --smoke-test

# Pre-fill the field and open the preview sheet
SIMCTL_CHILD_PREVIEW_URL="https://example.com/page" xcrun simctl launch booted com.downloadkit.app

# Start on a specific tab
SIMCTL_CHILD_SHOW_TAB=library xcrun simctl launch booted com.downloadkit.app
```

## Scope and limitations

- **Platform lock-in is deliberate.** YouTube, TikTok, Instagram and similar services sign
  their media URLs and protect them with DRM; downloading them requires a server-side
  extractor and violates their terms. This app only handles links it can resolve over plain
  HTTP, and it never bypasses DRM or paywalls.
- **Simulator quirk:** `AVAssetExportSession` fails on the simulator (`AVFoundationErrorDomain -11800`).
  The concatenated stream is still saved (`.mp4` for fMP4, `.ts` for legacy TS) and the app
  falls back gracefully; verify remuxing on a physical device.
- Downloads use a foreground `URLSession`; long transfers pause when the app is suspended.
  Switch to a background session (with `handleEventsForBackgroundURLSession`) for background transfers.
- No resume support yet — a failed download restarts from zero.
- Subtitle renditions are ignored; audio is muxed from the default rendition only.

## Before shipping to the App Store

- Replace `com.downloadkit.app` with your own bundle id and set a development team.
- App icon lives in `Sources/Resources/Assets.xcassets/AppIcon.appiconset` — regenerate with your brand.
- `NSAllowsArbitraryLoads` is enabled because users can supply `http://` media. Explain this in
  App Review notes; alternatively restrict to `NSAllowsArbitraryLoadsForMedia`.
- Guideline 5.2.3 (copyright) is the main rejection risk for downloader apps: keep the in-app
  notice ("only download content you have permission to save"), avoid naming third-party
  platforms in the metadata, and be ready to explain the DRM stance.
- Privacy: no analytics, no accounts, no network calls except the URLs the user provides.
