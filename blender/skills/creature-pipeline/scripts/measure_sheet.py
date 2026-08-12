"""Measure a concept TURNAROUND the same way measure_silhouette.py measures a mesh.

Splits the sheet into views by empty columns, then reports each view's aspect and
band profile. The point is that the two scripts produce directly comparable numbers,
so "does the model match the sheet" stops being a matter of opinion.

    python measure_sheet.py <sheet.png>

For a quadruped the widest-aspect view is the PROFILE and the narrowest is the
front/rear, which is how the model's side/front are matched to it.
"""
import sys
from PIL import Image
import numpy as np

path = sys.argv[1]
im = Image.open(path).convert("RGB")
a = np.asarray(im).astype(float)
lum = a.mean(2)
bg = np.percentile(lum, 20)
mask = lum > bg + 9

cols = mask.any(0)
runs, s = [], None
for x, v in enumerate(cols):
    if v and s is None:
        s = x
    if not v and s is not None:
        if x - s > 40:
            runs.append((s, x))
        s = None
if s is not None:
    runs.append((s, len(cols)))

out = []
for i, (x0, x1) in enumerate(runs):
    sub = mask[:, x0:x1]
    rows = np.nonzero(sub.any(1))[0]
    y0, y1 = rows.min(), rows.max()
    W, H = x1 - x0, y1 - y0 + 1
    prof = []
    for k in range(10):
        band = sub[y0 + int(H * k / 10): y0 + int(H * (k + 1) / 10)]
        w = np.nonzero(band.any(0))[0]
        prof.append(int(round(100.0 * (w.max() - w.min() + 1) / W)) if len(w) else 0)
    out.append((W / float(H), prof))
    print("SHEETVIEW %d  aspect %.2f  bands %s"
          % (i, W / float(H), " ".join("%3d" % p for p in prof)))

if out:
    asp = [o[0] for o in out]
    print("SHEETSPAN narrowest %.2f (front/rear)   widest %.2f (profile)"
          % (min(asp), max(asp)))
