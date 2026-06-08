import sys, subprocess
try:
    import pypdf
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "pypdf"], check=True)
    import pypdf

src = r"c:\New project\CAD watroba\KWOD_koncepcja.pdf"
out = r"c:\New project\CAD watroba\_tools\concept.txt"
reader = pypdf.PdfReader(src)
parts = []
for i, page in enumerate(reader.pages):
    parts.append(f"===== PAGE {i+1} =====")
    parts.append(page.extract_text() or "")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(parts))
print("OK wrote", out, "pages:", len(reader.pages))
