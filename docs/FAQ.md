# FluxKit FAQ

## Why can't I download a Douyin / TikTok / YouTube / Instagram link?

Because those apps never put a downloadable video file on the share page.

When you share a link, you get a **page** (for example `v.douyin.com/xxxx`), not a video. That page
loads the video later through an API that:

1. requires the app's own session/cookies, and
2. signs every request with a short-lived token (Douyin's `a_bogus`, TikTok's `X-Bogus`, …),
3. returns a playback URL that expires within minutes and is tied to that session.

FluxKit only runs on your iPhone — it does not have a server that could call those APIs, and it
deliberately does not try to fake their signatures. Even if it did, the trick would break every
time the platform changes its API, and it would go against their terms.

That is why the app rejects these hosts immediately with a clear message instead of downloading an
HTML page and failing later.

## What can I paste instead?

- A **direct video link**, usually ending in `.mp4`, `.mov`, `.m4v`, `.webm`, `.mp3`, `.m4a`, …
- An **HLS playlist** (`.m3u8`), including playlists behind a normal HTTP link.
- A **public web page** that embeds a video with `og:video`, a `<video>` tag, `<source>` or JSON-LD
  `contentUrl` — the app fetches the page and picks the media URL out of it.
- A **podcast RSS/Atom feed** — the app lists episodes with date, duration and size, and downloads
  the enclosure URL you pick.

If the page needs a login, a subscription, or DRM playback, it won't work.

## The link worked in the browser — why not here?

Browsers can play protected streams because the site gives the browser a session and the player
handles the signing. A downloader only receives the URL you paste; if that URL does not point at a
media file or a page that exposes one, there is nothing to download.

## Can support be added later?

Only with a server-side extractor (a service that resolves the link and returns a file). That means
running infrastructure, dealing with rate limits and legal terms, and keeping up with each platform.
If you want that, it should be a deliberate product decision — not something the on-device app can
fake.
