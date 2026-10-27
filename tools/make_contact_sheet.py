"""Assemble renders from tools/blender/ck_render_views.py into labelled contact sheets.

Usage (project root):  python tools/make_contact_sheet.py [render_dir]
Writes <render_dir>/contact_views.png and <render_dir>/contact_clips.png (needs Pillow).
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RDIR = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "references", "renders", "crx9")


def sheet(rows, out, label_w=170):
    """rows: [(label, [image paths])]"""
    imgs = [[Image.open(os.path.join(ROOT, p)) for p in paths] for _, paths in rows]
    w, h = imgs[0][0].size
    cols = max(len(r) for r in imgs)
    canvas = Image.new("RGB", (label_w + cols * w, len(rows) * h), (12, 12, 16))
    draw = ImageDraw.Draw(canvas)
    for r, ((label, _), row) in enumerate(zip(rows, imgs)):
        draw.text((8, r * h + h // 2 - 6), label, fill=(230, 60, 60))
        for c, im in enumerate(row):
            canvas.paste(im.convert("RGB"), (label_w + c * w, r * h))
    canvas.save(out)
    print("wrote", os.path.relpath(out, ROOT))


def main():
    rep = json.load(open(os.path.join(RDIR, "render_manifest.json")))
    sheet([("bind pose: " + " | ".join(os.path.basename(v)[5:-4] for v in rep["views"]), rep["views"])],
          os.path.join(RDIR, "contact_views.png"), label_w=0)
    clips = list(rep["clips"].items())
    for i in range(0, len(clips), 8):
        sheet(clips[i:i + 8], os.path.join(RDIR, f"contact_clips_{i // 8 + 1}.png"))


if __name__ == "__main__":
    main()
