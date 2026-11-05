#!/usr/bin/env python3
"""Render the public web pages into ``site/``.

Single source of truth: the Markdown files under ``docs/``. This script has no
third-party dependencies on purpose — it runs with the system Python, so the
site can be rebuilt on any machine (or in a CI step) with:

    python3 scripts/build_site.py
    # or: make site

Routes produced (exactly the URLs the app and App Store Connect point at):

    /privacy-policy   <- docs/privacy-policy.md
    /terms-of-service <- docs/terms-of-use.md
    /support          <- docs/support.md

The output directory is what you publish to Cloudflare Pages / GitHub Pages /
any static host. It contains no JavaScript, no external fonts, no CDN calls.
"""

from __future__ import annotations

import html
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = ROOT / "site"

SITE_NAME = "FluxKit"
COMPANY = "OpenKit"
CONTACT = "support@openkit.cloud"

PAGES = [
    ("privacy-policy.md", "privacy-policy", "Privacy Policy", "隐私政策"),
    ("terms-of-use.md", "terms-of-service", "Terms of Use", "使用条款"),
    ("support.md", "support", "Support", "支持"),
]


# --------------------------------------------------------------------------- #
# Markdown (deliberately small subset: headings, lists, paragraphs, emphasis)
# --------------------------------------------------------------------------- #

CODE_TOKEN = "\x00{}\x00"


def inline(text: str) -> str:
    """Escape HTML, then apply the inline markdown used in docs/."""
    escaped = html.escape(text, quote=False)

    # Pull code spans out first so their contents are not re-processed.
    snippets: list[str] = []

    def stash(match: re.Match[str]) -> str:
        snippets.append("<code>" + match.group(1) + "</code>")
        return CODE_TOKEN.format(len(snippets) - 1)

    escaped = re.sub(r"`([^`]+)`", stash, escaped)

    # [label](url) and bare https:// links.
    escaped = re.sub(
        r"\[([^\]]+)\]\(((?:https?://|/|#)[^\s)]+)\)",
        r'<a href="\2">\1</a>',
        escaped,
    )
    def autolink(match: re.Match[str]) -> str:
        raw = match.group(1)
        url = raw.rstrip(".,;:")
        tail = raw[len(url):]
        return '<a href="{0}">{0}</a>{1}'.format(url, tail)

    escaped = re.sub(r"(?<![\"'=>])(https?://[^\s<)\]]+)", autolink, escaped)

    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", escaped)

    for index, snippet in enumerate(snippets):
        escaped = escaped.replace(CODE_TOKEN.format(index), snippet)
    return escaped


CJK = r"\u2e80-\u9fff\u3000-\u303f\uff00-\uffef"
_NO_SPACE_AFTER = re.compile(r"[{0}]$".format(CJK))
_NO_SPACE_BEFORE = re.compile(r"^[{0}]".format(CJK))


def join_lines(lines: list[str]) -> str:
    """Join wrapped lines, but never insert a space between CJK characters."""
    out = lines[0].strip()
    for line in lines[1:]:
        nxt = line.strip()
        if _NO_SPACE_AFTER.search(out) and _NO_SPACE_BEFORE.search(nxt):
            out += nxt
        else:
            out += " " + nxt
    return out


def render_blocks(markdown: str) -> tuple[str, str]:
    """Return (page title, html body)."""
    title = SITE_NAME
    blocks = re.split(r"\n\s*\n", markdown.strip())
    out: list[str] = []

    for block in blocks:
        lines = [line.rstrip() for line in block.splitlines() if line.strip()]
        if not lines:
            continue

        if len(lines) == 1 and lines[0].startswith("# "):
            title = lines[0][2:].strip()
            continue

        if all(line.startswith("## ") for line in lines):
            for line in lines:
                out.append("<h2>{}</h2>".format(inline(line[3:].strip())))
            continue

        if all(re.match(r"^[-*] ", line) for line in lines):
            items = "".join(
                "<li>{}</li>".format(inline(line[2:].strip())) for line in lines
            )
            out.append("<ul>{}</ul>".format(items))
            continue

        if all(re.match(r"^\d+\. ", line) for line in lines):
            items = "".join(
                "<li>{}</li>".format(inline(re.sub(r"^\d+\. ", "", line).strip()))
                for line in lines
            )
            out.append("<ol>{}</ol>".format(items))
            continue

        out.append("<p>{}</p>".format(inline(join_lines(lines))))

    return title, "\n".join(out)


# --------------------------------------------------------------------------- #
# Layout
# --------------------------------------------------------------------------- #

STYLE = """:root {
  color-scheme: light dark;
  --bg: #ffffff;
  --fg: #16181d;
  --muted: #5c6470;
  --line: #e6e8ec;
  --accent: #4a5cf5;
  --card: #f7f8fa;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d0f14;
    --fg: #eceef2;
    --muted: #9aa3b2;
    --line: #23262d;
    --accent: #8b96ff;
    --card: #151822;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
    "Hiragino Sans GB", "Microsoft YaHei", Roboto, Helvetica, Arial, sans-serif;
}
.wrap { max-width: 46rem; margin: 0 auto; padding: 0 1.25rem; }
header.site { border-bottom: 1px solid var(--line); }
header.site .wrap {
  display: flex; align-items: center; gap: 1rem;
  height: 3.75rem; flex-wrap: wrap;
}
.brand { font-weight: 700; letter-spacing: -0.01em; text-decoration: none; color: var(--fg); }
nav { display: flex; gap: 1.1rem; margin-left: auto; }
nav a { color: var(--muted); text-decoration: none; font-size: 0.9rem; }
nav a:hover, nav a[aria-current="page"] { color: var(--accent); }
main { padding: 2.75rem 0 4rem; }
h1 { font-size: 1.9rem; line-height: 1.2; letter-spacing: -0.02em; margin: 0 0 0.5rem; }
h2 { font-size: 1.15rem; margin: 2.2rem 0 0.6rem; letter-spacing: -0.01em; }
p, li { color: var(--fg); }
li { margin: 0.3rem 0; }
a { color: var(--accent); }
hr { border: 0; border-top: 1px solid var(--line); margin: 2.5rem 0; }
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.9em; background: var(--card); padding: 0.1em 0.35em;
  border-radius: 4px;
}
footer.site {
  border-top: 1px solid var(--line); padding: 1.5rem 0 2.5rem;
  color: var(--muted); font-size: 0.85rem;
}
footer.site a { color: var(--muted); }
.cards { display: grid; gap: 0.85rem; margin: 2rem 0 0; padding: 0; list-style: none; }
@media (min-width: 34rem) { .cards { grid-template-columns: 1fr 1fr 1fr; } }
.cards a {
  display: block; padding: 1rem 1.1rem; border: 1px solid var(--line);
  border-radius: 14px; background: var(--card); text-decoration: none; color: var(--fg);
}
.cards span { display: block; color: var(--muted); font-size: 0.85rem; margin-top: 0.2rem; }
.lede { color: var(--muted); font-size: 1.02rem; }
.contact {
  margin: 2rem 0 0; padding: 1rem 1.1rem; border: 1px solid var(--line);
  border-radius: 14px; background: var(--card);
}
@media print {
  header.site, footer.site, nav { display: none; }
  body { background: #fff; color: #000; }
  main { padding: 0; }
}
"""


def layout(
    slug: str, title: str, body: str, brand: str = SITE_NAME, show_h1: bool = True
) -> str:
    year = date.today().year
    heading = "<h1>{}</h1>\n".format(html.escape(title)) if show_h1 else ""
    nav = "\n".join(
        '        <a href="/{slug}"{current}>{en}</a>'.format(
            slug=page_slug,
            current=' aria-current="page"' if page_slug == slug else "",
            en=page_en,
        )
        for _, page_slug, page_en, _ in PAGES
    )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(brand)} — {html.escape(title)}">
<meta name="color-scheme" content="light dark">
<style>{STYLE}</style>
</head>
<body>
<header class="site">
  <div class="wrap">
    <a class="brand" href="/">{html.escape(brand)}</a>
    <nav>
{nav}
    </nav>
  </div>
</header>
<main>
  <div class="wrap">
{heading}{body}
  </div>
</main>
<footer class="site">
  <div class="wrap">
    © {year} {COMPANY} · <a href="mailto:{CONTACT}">{CONTACT}</a> ·
    <a href="/privacy-policy">Privacy</a> · <a href="/terms-of-service">Terms</a>
  </div>
</footer>
</body>
</html>
"""


LANDING = """<h1>FluxKit</h1>
<p class="lede">An offline media saver for iPhone: HLS playlists, direct links, and podcast
feeds. Paste a link, tap Download, keep it offline.</p>

<ul class="cards">
  <li><a href="/support">Support<span>Help, FAQ, and contact</span></a></li>
  <li><a href="/privacy-policy">Privacy Policy<span>What stays on your device</span></a></li>
  <li><a href="/terms-of-service">Terms of Use<span>License and subscriptions</span></a></li>
</ul>

<div class="contact">
  <p><strong>Contact</strong> — <a href="mailto:{contact}">{contact}</a></p>
  <p class="lede">FluxKit downloads media from links you provide. It does not host content and does
  not bypass DRM, logins, or paywalls. Only save media you have the right to keep.</p>
</div>
""".format(contact=CONTACT)

NOT_FOUND = """<h1>Page not found</h1>
<p class="lede">That URL does not exist. Try one of these:</p>
<ul>
  <li><a href="/support">Support</a></li>
  <li><a href="/privacy-policy">Privacy Policy</a></li>
  <li><a href="/terms-of-service">Terms of Use</a></li>
</ul>
"""

REDIRECTS = """/privacy /privacy-policy 301
/terms /terms-of-service 301
/policy /privacy-policy 301
/faq /support 301
/help /support 301
/index.html / 301
"""

HEADERS = """/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: SAMEORIGIN
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(), microphone=(), camera=(), interest-cohort=()

/privacy-policy/*
  Cache-Control: public, max-age=3600

/terms-of-service/*
  Cache-Control: public, max-age=3600

/support/*
  Cache-Control: public, max-age=3600
"""


def main() -> int:
    OUT.mkdir(exist_ok=True)

    for source, slug, english, _zh in PAGES:
        path = DOCS / source
        if not path.exists():
            print(f"missing source: {path}", file=sys.stderr)
            return 1
        title, body = render_blocks(path.read_text(encoding="utf-8"))
        target = OUT / slug
        target.mkdir(parents=True, exist_ok=True)
        (target / "index.html").write_text(
            layout(slug, title, body), encoding="utf-8"
        )
        print(f"  {source} -> site/{slug}/index.html")

    (OUT / "index.html").write_text(
        layout("", SITE_NAME, LANDING, show_h1=False), encoding="utf-8"
    )
    (OUT / "404.html").write_text(
        layout("", "Not found", NOT_FOUND, show_h1=False), encoding="utf-8"
    )
    (OUT / "_redirects").write_text(REDIRECTS, encoding="utf-8")
    (OUT / "_headers").write_text(HEADERS, encoding="utf-8")
    (OUT / "robots.txt").write_text(
        "User-agent: *\nAllow: /\n", encoding="utf-8"
    )
    print("  -> site/index.html, site/404.html, site/_redirects, site/_headers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
