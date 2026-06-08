# -*- coding: utf-8 -*-
import sys, subprocess, base64, re, os

try:
    import markdown
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "markdown"], check=True)
    import markdown

PROJ = r"c:\New project\CAD watroba"
RAPORT_DIR = os.path.join(PROJ, "raport")
MD = os.path.join(RAPORT_DIR, "KWOD_Salauyou_Yermakova.md")
HTML = os.path.join(RAPORT_DIR, "KWOD_Salauyou_Yermakova.html")

with open(MD, encoding="utf-8") as f:
    text = f.read()

# Remove the first H1 + the bold meta block (they go on the cover page instead)
lines = text.splitlines()
# drop everything up to and including the '---' that ends the header meta block
cut = 0
for i, ln in enumerate(lines):
    if ln.strip() == "---":
        cut = i + 1
        break
body_md = "\n".join(lines[cut:]).lstrip("\n")

html_body = markdown.markdown(
    body_md,
    extensions=["tables", "fenced_code", "sane_lists", "toc"],
)

# Embed images as base64 data URIs
def embed(m):
    rel = m.group(1)
    path = os.path.join(RAPORT_DIR, rel.replace("/", os.sep))
    if not os.path.isfile(path):
        return m.group(0)
    ext = os.path.splitext(path)[1].lstrip(".").lower()
    mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif"}.get(ext, "image/png")
    with open(path, "rb") as fh:
        data = base64.b64encode(fh.read()).decode("ascii")
    return f'src="data:{mime};base64,{data}"'

html_body = re.sub(r'src="([^"]+)"', embed, html_body)

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
* { box-sizing: border-box; }
body {
  font-family: "Segoe UI", "Aptos", Calibri, Arial, sans-serif;
  color: #1f2733; font-size: 11pt; line-height: 1.5; margin: 0;
}
.cover {
  height: 247mm; display: flex; flex-direction: column; justify-content: center;
  text-align: center; page-break-after: always;
  background: #ffffff; color: #1f2733; padding: 24mm 18mm;
}
.cover .kicker { letter-spacing: 4px; text-transform: uppercase; font-size: 12pt; color: #5a6b7d; }
.cover .rule { width: 70mm; height: 2px; background: #12446e; margin: 16px auto 22px; }
.cover h1 { font-size: 28pt; line-height: 1.22; margin: 10px 0 8px; font-weight: 700; color: #12446e; }
.cover .sub { font-size: 13pt; color: #3a4654; max-width: 150mm; margin: 0 auto 30px; }
.cover .authors { margin-top: 8px; font-size: 16pt; font-weight: 600; color: #1f2733; }
.cover .authors .name { display: block; margin: 6px 0; }
.cover .meta { margin-top: 34px; font-size: 10.5pt; color: #5a6b7d; }
h1, h2, h3 { color: #12446e; line-height: 1.25; }
h2 { font-size: 16pt; margin: 22px 0 8px; padding-bottom: 5px; border-bottom: 2px solid #d8e3ee; }
h3 { font-size: 12.5pt; margin: 16px 0 5px; color: #1a5a86; }
p { margin: 7px 0; }
a { color: #15507a; text-decoration: none; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 9.6pt; }
th, td { border: 1px solid #c9d6e3; padding: 6px 8px; text-align: left; vertical-align: top; }
th { background: #eaf1f8; color: #12446e; }
tr:nth-child(even) td { background: #f6f9fc; }
code { background: #eef2f7; padding: 1px 5px; border-radius: 4px; font-size: 9.5pt; }
pre { background: #f4f7fa; border: 1px solid #dce5ee; border-radius: 6px; padding: 10px; overflow: auto; }
blockquote { margin: 10px 0; padding: 8px 14px; background: #fff8e6;
  border-left: 4px solid #e0a93b; border-radius: 4px; color: #5b4a25; }
img { max-width: 92%; display: block; margin: 8px auto; border: 1px solid #cfd9e3;
  border-radius: 6px; box-shadow: 0 1px 4px rgba(0,0,0,.12); }
figure, p > img { page-break-inside: avoid; }
h2, h3 { page-break-after: avoid; }
ul, ol { margin: 6px 0 6px 4px; padding-left: 22px; }
li { margin: 3px 0; }
"""

COVER = """
<div class="cover">
  <div class="kicker">Projekt KWOD &middot; CAD</div>
  <div class="rule"></div>
  <h1>System CAD do objętościowej oceny<br>wątroby i zmian ogniskowych w CT</h1>
  <div class="sub">Raport z projektu — prototyp w środowisku MATLAB (segmentacja, objętości, metryki jakości, wizualizacja)</div>
  <div class="authors">
    <span class="name">Alina Yermakova</span>
    <span class="name">Mikita Salauyou</span>
  </div>
  <div class="meta">Dane testowe: IRCAD 3Dircadb1 &middot; Środowisko: MATLAB R2025b</div>
</div>
"""

full = f"""<!DOCTYPE html>
<html lang="pl"><head><meta charset="utf-8">
<title>Raport KWOD — Salauyou, Yermakova</title>
<style>{CSS}</style></head>
<body>{COVER}<main>{html_body}</main></body></html>"""

with open(HTML, "w", encoding="utf-8") as f:
    f.write(full)
print("OK wrote", HTML, len(full), "chars")
