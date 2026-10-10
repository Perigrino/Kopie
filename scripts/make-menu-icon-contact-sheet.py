#!/usr/bin/env python3
"""Builds assets/menu-icon-preview.html — the menu-bar icon contact sheet.

The app-icon sheet can get away with showing large artwork, because the app
icon is looked at up close. A menu-bar glyph is judged at 18pt, at a distance,
on a bar that may be light or dark — so this sheet renders every candidate at
true 1:1 menu-bar pixels, flanked by system glyphs for weight comparison, with
a distance strip alongside.

Template glyphs are shown with `invert(1)` on the dark bar, which is what macOS
does when it tints the alpha mask to match the menu label.
"""
import base64
import html
import os

SRC = "assets/menu-icon-sources"
OUT = "assets/menu-icon-preview.html"

CONCEPTS = [
    ("clipboard-spark", "Clipboard + spark",
     "Solid clipboard with the spark knocked out of it. Mirrors the app icon, and the knockout keeps both shapes readable at 18px."),
    ("card-stack", "Card stack",
     "Two offset cards — reads as a history of copies, not a clipboard. Chunky diagonal silhouette, rare in menu bars."),
    ("cmd", "⌘ cloverleaf",
     "Bare ⌘. Maximum distance legibility and unique among menu-bar pictograms, but reads as an action rather than as Kopie."),
    ("paste-arrow", "Paste arrow",
     "Clipboard with a knocked-out paste arrow pointing into it. Action-led — says what the app does."),
    ("spark", "Spark",
     "The app icon's spark alone. Maximally distinctive and very fast to find, but drops the clipboard meaning entirely."),
]

# Stand-ins for the neighbours it has to compete with.
NEIGHBOURS_BEFORE = ["☀", "♪", "☁"]
NEIGHBOURS_AFTER = ["⚙", "🔍", "🔋"]


def uri(concept, style, state, px):
    path = os.path.join(SRC, f"{concept}-{style}-{state}@{px}.png")
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def glyph(concept, style, state, *, dark=False, size=18):
    """An 18pt glyph, tinted the way macOS would tint a template image."""
    tint = "invert(1)" if dark else ""
    return (f'<img src="{uri(concept, style, state, 36)}" width="{size}" height="{size}" '
            f'alt="" style="display:block;filter:{tint};" class="glyph">')


def bar(concept, style, state, *, dark=False):
    """A strip of menu bar with the candidate sat among its neighbours."""
    bg = ("linear-gradient(#3b3b3d,#2b2b2d);border-bottom:1px solid #1b1b1d;"
          "box-shadow:inset 0 -1px 0 rgba(255,255,255,.08);") if dark else (
          "linear-gradient(#f7f7f7,#e9e9ea);border-bottom:1px solid #d5d5d7;"
          "box-shadow:inset 0 -1px 0 rgba(255,255,255,.7);")
    fg = "#f2f2f2" if dark else "#1d1d1f"
    marks = "".join(f'<span class="mark" style="color:{fg}">{g}</span>'
                    for g in NEIGHBOURS_BEFORE)
    after = "".join(f'<span class="mark" style="color:{fg}">{g}</span>'
                    for g in NEIGHBOURS_AFTER)
    return (f'<div class="bar" style="{bg}">'
            f'{marks}<span class="mine">{glyph(concept, style, state, dark=dark)}</span>{after}'
            f'</div>')


def distance(concept, style, state, *, dark=False):
    """1:1, then half size, then blurred — the honest test of 'noticeable'."""
    bg = "#2b2b2d" if dark else "#e9e9ea"
    fg = "#f2f2f2" if dark else "#1d1d1f"
    tint = "invert(1)" if dark else ""
    cells = []
    for label, px, filt in [
        ("1:1", 18, ""),
        ("½ size", 9, ""),
        ("at distance", 18, "blur(.55px) contrast(.88);opacity:.85;"),
    ]:
        cells.append(
            f'<div class="dcell" style="background:{bg}">'
            f'<img src="{uri(concept, style, state, 36)}" width="{px}" height="{px}" '
            f'alt="" style="filter:{tint}{filt}">'
            f'<div class="dlab" style="color:{fg}">{label}</div></div>')
    return f'<div class="dstrip">{"".join(cells)}</div>'


cards = []
for concept, name, blurb in CONCEPTS:
    # The four bar mocks: each style on each bar tint it was designed for,
    # so the sheet shows the colour versions in their intended context.
    style_rows = []
    for style, state, dark, caption in [
        ("template", "idle", False, "Template · light bar"),
        ("template", "idle", True,  "Template · dark bar"),
        ("colorLight", "idle", False, "Coral · light bar"),
        ("colorDark", "idle", True,  "Coral · dark bar"),
    ]:
        style_rows.append(
            f'<div class="row"><div class="cap">{caption}</div>'
            f'{bar(concept, style, state, dark=dark)}</div>')

    cards.append(f"""
  <div class="card">
    <div class="head">
      <div class="num">{CONCEPTS.index((concept, name, blurb)) + 1}</div>
      <div><div class="ttl">{html.escape(name)}</div>
      <div class="key">{html.escape(concept)}</div></div>
    </div>
    <p class="blurb">{html.escape(blurb)}</p>
    {"".join(style_rows)}
    <div class="sec">Idle vs paused — light bar</div>
    <div class="pair">
      <div class="row"><div class="cap">Idle</div>{bar(concept, "template", "idle")}</div>
      <div class="row"><div class="cap">Paused</div>{bar(concept, "template", "paused")}</div>
    </div>
    <div class="sec">Distance test — light bar / dark bar</div>
    {distance(concept, "template", "idle")}
    {distance(concept, "template", "idle", dark=True)}
  </div>""")

# A single strip of all five side by side, so relative weight is obvious.
glance = "".join(
    f'<div class="gitem">{bar(c, "template", "idle")}'
    f'<div class="glab">{html.escape(n)}</div></div>'
    for c, n, _ in CONCEPTS)

page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kopie — menu bar icon options</title>
<style>
  body {{ margin:0; background:#f2f2f7;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
  .wrap {{ max-width:900px; margin:0 auto; padding:32px 24px 64px; }}
  h1 {{ font-size:22px; margin:0 0 6px; }}
  .sub {{ font-size:14px; color:#555; margin:0 0 26px; line-height:1.55; }}
  code {{ background:#e5e5ea; padding:1px 6px; border-radius:4px; }}
  .glancebox {{ background:#fff; border:1px solid #ddd; border-radius:14px;
                padding:18px; margin-bottom:26px; }}
  .gitem {{ display:inline-block; margin-right:18px; vertical-align:top; }}
  .glab {{ font-size:11px; color:#666; margin-top:6px; text-align:center;
           font-weight:600; }}
  .card {{ background:#fff; border:1px solid #ddd; border-radius:14px;
           padding:20px; margin-bottom:22px; box-shadow:0 2px 8px rgba(0,0,0,.05); }}
  .head {{ display:flex; align-items:center; gap:12px; margin-bottom:8px; }}
  .num {{ width:26px; height:26px; border-radius:8px; background:#1c1c1e;
          color:#fff; font:700 13px/26px -apple-system,sans-serif; text-align:center; }}
  .ttl {{ font-size:16px; font-weight:700; color:#1c1c1e; }}
  .key {{ font-size:11px; color:#999; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }}
  .blurb {{ font-size:13px; color:#555; line-height:1.55; margin:0 0 16px; }}
  .sec {{ font:600 11px/1.4 -apple-system,sans-serif; letter-spacing:.08em;
          text-transform:uppercase; color:#999; margin:18px 0 8px; }}
  .row {{ margin-bottom:10px; }}
  .cap {{ font-size:11px; color:#888; margin-bottom:4px; }}
  .pair {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; }}
  .bar {{ height:26px; border-radius:6px; display:flex; align-items:center;
          padding:0 10px; overflow:hidden; }}
  .mark {{ font-size:15px; opacity:.75; margin-right:11px; line-height:1; }}
  .mine {{ margin-right:11px; }}
  .glyph {{ margin-top:1px; }}
  .dstrip {{ display:flex; gap:8px; margin-bottom:8px; }}
  .dcell {{ flex:1; height:54px; border-radius:6px; display:flex;
            flex-direction:column; align-items:center; justify-content:center; gap:3px; }}
  .dlab {{ font-size:10px; opacity:.7; }}
</style></head>
<body><div class="wrap">
  <h1>Kopie — choose the menu bar icon</h1>
  <p class="sub">
    Every candidate below is drawn solid rather than as a hairline outline — the
    current icon is a thin outline that goes sub-pixel at 18pt and antialiases
    into grey, which is why it reads as faint. Menu bar glyphs are
    <b>template images</b>: macOS discards the colour and tints the alpha to
    match the menu label, so legibility here has to come from filled mass and
    silhouette, not hue. Generated by
    <code>scripts/icon-sources/generate-menu-icon.swift</code>.
  </p>

  <div class="glancebox">
    <div class="sec" style="margin-top:0">At a glance — all five on a light bar, 1:1</div>
    {glance}
  </div>

  {"".join(cards)}
</div></body></html>"""

with open(OUT, "w") as f:
    f.write(page)
print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB)")
