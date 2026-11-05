# App Review notes — FluxKit

## What FluxKit does

FluxKit is an offline media saver for content the user is allowed to keep: HLS playlists
(`.m3u8`), direct media files, and podcast RSS/Atom feeds. The user pastes a link (or shares one
from another app), the app probes it, finds the media behind it, and downloads it with a
background `URLSession` so it is available offline.

The app has no account, no analytics, no advertising, and no server of its own. Downloads go
directly from the source to the device.

## How to test

1. Launch the app.
2. Paste this public HLS test stream and tap **Download**:
   `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8`
3. Paste a direct MP4 link, for example:
   `https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4`
4. To test podcasts, paste a public feed:
   `https://feeds.npr.org/510289/podcast.xml`
   The app shows the show artwork, episode list (date, duration, size) and a download button per
   episode.
5. Open the **Downloads** tab to see progress, and play the result offline from **Library**.

## Scope and limitations (also shown in the app)

FluxKit does **not** break DRM, bypass logins/paywalls, remove watermarks, or extract media from
platform-locked services. Links whose playback URL is created per-session inside another company's
app (for example short-lived signed video URLs) are rejected before any download attempt, with an
explanation. The app displays "Only download videos you have the right to save."

## Background execution

Progressive downloads use a background `URLSession`, so a transfer can finish while the app is
suspended. The app also reconnects to the session after a relaunch via `taskDescription`. HLS jobs
keep per-segment files on disk so they resume after a pause, crash or relaunch.

The app declares the **audio** background mode only to let playback continue with the screen
locked (podcasts and video), with standard lock-screen metadata and play/pause/seek controls. It
does not record audio, does not use the microphone, and does not run any other background mode.

## Subtitles, Picture in Picture, Files

- Subtitles: the app lists subtitle/audio tracks embedded in the downloaded file (AVMediaSelectionGroup)
  and downloads the subtitle renditions declared by an HLS master playlist as local WebVTT sidecars.
  Rendering uses a simple text overlay; no third-party player or DRM component is involved.
- Picture in Picture uses `AVPictureInPictureController` and continues standard playback; the audio
  background mode is only for media playback, not recording.
- Downloads are stored in the app's Documents directory so they appear in Files → On My iPhone →
  FluxKit → Media. "Import from Files" copies a user-selected video/audio file into the library.
  Nothing is uploaded.

## Subscription (FluxKit Pro)

- Two auto-renewable subscriptions (`cloud.fluxkit.pro.monthly`, `cloud.fluxkit.pro.yearly`) in
  one group. Pro unlocks 4-at-a-time downloads and podcast auto-download. The core downloader,
  HLS support, subtitles, PiP, and Files access remain free.
- Purchases are processed by Apple StoreKit 2; **RevenueCat** validates receipts and syncs the
  `pro` entitlement across devices. The app stores no receipts and shows no payment details.
  RevenueCat receives an anonymous app user ID and purchase history only.
- Restore purchases is available on the paywall and in Settings; Terms and Privacy links are shown
  on the paywall.

## Content rights

FluxKit does not bundle, curate, index, or distribute any third-party content. It ships with no
media files, no content catalog, and no search or discovery feature. It is a download client for
links the user already has: the user pastes a URL, shares one from another app, or imports a file
from the Files app, and the app performs a standard HTTP request to the origin server the user
chose — the same request a browser would make.

There is no DRM circumvention, no login or paywall bypass, no watermark removal, and no extraction
from platform-locked services; such links are rejected with an explanation. Podcast support reads
only the public enclosure URLs published in a feed's RSS.

The app displays "Only download videos you have the right to save", and the Terms of Use require
the user to confirm they hold the rights to the media they save. Rights to any saved media remain
with the user and the original publisher.

## Privacy

- App Privacy: RevenueCat receives an anonymous app user ID and **Purchase History** (product,
  renewal, expiration, cancellation). Not linked to the user's identity, not used for tracking.
  Nothing else is collected: no account, no analytics, no advertising, no location.
- The only third-party SDK is **RevenueCat** (subscription receipt validation). Its own
  `PrivacyInfo.xcprivacy` ships inside the bundle.
- The only network requests are the ones needed to resolve and download the URL the user pasted,
  plus RevenueCat's calls for offerings and entitlement status.
- `PrivacyInfo.xcprivacy` is bundled; no required-reason APIs beyond UserDefaults for preferences.
- Content rights are declared as **Yes** (the app accesses third-party content at the user's
  direction, but bundles none).

## Contact

support@openkit.cloud
