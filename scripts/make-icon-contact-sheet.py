#!/usr/bin/env python3
"""Builds assets/icon-preview.html — a contact sheet of the 10 Kopie icon designs."""
import base64
import html
import os

PREVIEWS = "/tmp/kopie-icons/preview"
OUT = "assets/icon-preview.html"

# (design suffix, short name, description)
DESIGNS = [
    ("6",  "Glass Clipboard", "Blue frosted clipboard with a star — classic clipboard motif"),
    ("7",  "Glass K",         "Dark glass monogram 'K' with a gradient underline"),
    ("8",  "Glass Stack",     "Teal overlapping frosted sheets with a star badge — history"),
    ("9",  "Glass Rainbow",   "Indigo glass doc with vivid rainbow lines"),
    ("10", "Glass Spark",     "Coral glass, outlined clipboard with a white star"),
    ("11", "Glass Clock",     "Blue clock with a circular refresh arrow — retention"),
    ("12", "Glass Heart",     "Rose heart with a specular highlight — favorites"),
    ("13", "Glass Bolt",      "Amber lightning bolt — speed"),
    ("14", "Glass Gear",      "Slate gear with teeth — settings"),
    ("15", "Glass Mirror",    "Violet mirrored copy/paste panes with a gold plus badge"),
]

def data_uri(name):
    with open(os.path.join(PREVIEWS, name), "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

cards = []
for i, (suffix, name, desc) in enumerate(DESIGNS, start=1):
    uri = data_uri(f"design{suffix}.png")
    cards.append(f"""
    <div style="background:#fff;border:1px solid #ddd;border-radius:14px;padding:18px;
                display:flex;flex-direction:column;align-items:center;gap:10px;
                box-shadow:0 2px 8px rgba(0,0,0,.06);">
      <div style="font:600 12px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;color:#888;
                  letter-spacing:.08em;text-transform:uppercase;">Option {i}</div>
      <img src="{uri}" width="180" height="180" alt="{html.escape(name)}"
           style="border-radius:18px;box-shadow:0 4px 14px rgba(0,0,0,.18);">
      <div style="font:700 15px/1.3 -apple-system,Segoe UI,Roboto,sans-serif;color:#1c1c1e;">{html.escape(name)}</div>
      <div style="font:400 12px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:#666;
                  text-align:center;max-width:200px;">{html.escape(desc)}</div>
    </div>""")

page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>Kopie — app icon options</title></head>
<body style="margin:0;background:#f2f2f7;font-family:-apple-system,Segoe UI,Roboto,sans-serif;">
  <div style="max-width:1180px;margin:0 auto;padding:32px 24px 48px;">
    <h1 style="font-size:22px;margin:0 0 6px;">Kopie — choose your app icon</h1>
    <p style="font-size:14px;color:#555;margin:0 0 24px;">
      10 liquid-glass designs, generated from
      <code style="background:#e5e5ea;padding:1px 6px;border-radius:4px;">scripts/icon-sources/generate-icons-glass.swift</code>.
      Tell me the option number and I'll apply it everywhere — bundle icon, menu bar, popover, onboarding.
    </p>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:18px;">
      {"".join(cards)}
    </div>
  </div>
</body></html>"""

with open(OUT, "w") as f:
    f.write(page)
print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB)")
