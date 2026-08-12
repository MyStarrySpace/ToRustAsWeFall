"""Survey the Sapscrap turnaround: body, ring maw, limbs, horn.

Unlike the Ferrule (one flat silhouette panel) this creature has a four-view
turnaround, so the WIDTH axis is measured rather than invented. Front gives
breadth + the maw; side gives depth + limb stations; back cross-checks.

Gates: the shell is plum (green is the minimum channel by a clear margin), the
claws and teeth are desaturated bone, the ground shadow is pale and nearly
neutral - so shadow is excluded by requiring either saturation or darkness.
"""
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

BASE = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
        "reference-images/concept/fauna/turnarounds/")
VIEWS = {"front": "sapscraps-idle-01-front.png",
         "side": "sapscraps-idle-01-side.png",
         "back": "sapscraps-idle-01-back.png"}


def masks(path):
    """Body = everything that is neither the cream paper nor its soft shadow."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    h, w, _ = a.shape
    border = np.concatenate([a[:6].reshape(-1, 3), a[-6:].reshape(-1, 3),
                             a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    dist = np.abs(a - bg).sum(axis=2)
    hi = a.max(axis=2)
    lo = a.min(axis=2)
    sat = hi - lo
    r, g, b = a[..., 0], a[..., 1], a[..., 2]

    not_bg = dist > 34
    # the cast shadow is smooth, nearly neutral and still light
    shadow = not_bg & (sat < 16) & (hi > 168)
    body = not_bg & ~shadow
    body = ndimage.binary_closing(body, np.ones((5, 5)))
    body = ndimage.binary_fill_holes(body)
    body = ndimage.binary_opening(body, np.ones((3, 3)))
    lab, n = ndimage.label(body)
    if n:
        sizes = ndimage.sum(body, lab, range(1, n + 1))
        body = lab == (int(np.argmax(sizes)) + 1)

    shell = body & (sat >= 22) & (g <= r - 8)
    bone = body & (sat < 34) & (hi >= 110) & (hi < 215)
    dark = body & (hi < 72)                      # the maw throat
    return body, shell, bone, dark


def bbox(m):
    ys, xs = np.nonzero(m)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


out = {}
overlays = {}
for name, fn in VIEWS.items():
    path = BASE + fn
    body, shell, bone, dark = masks(path)
    x0, y0, x1, y1 = bbox(body)
    W, H = x1 - x0 + 1, y1 - y0 + 1
    view = {"bbox": [x0, y0, x1, y1], "w_px": W, "h_px": H,
            "w_over_h": round(W / H, 4)}

    # bone blobs = claws and teeth
    blab, bn = ndimage.label(bone)
    blobs = []
    for i in range(1, bn + 1):
        m = blab == i
        if m.sum() < 120:
            continue
        bx0, by0, bx1, by1 = bbox(m)
        ys, xs = np.nonzero(m)
        blobs.append({"area": int(m.sum()),
                      "bbox": [bx0, by0, bx1, by1],
                      "c": [round(float(xs.mean() - x0) / H, 4),
                            round(float(y1 - ys.mean()) / H, 4)],
                      "size": [round((bx1 - bx0) / H, 4), round((by1 - by0) / H, 4)]})
    blobs.sort(key=lambda d: -d["area"])
    view["bone_blobs"] = blobs[:20]
    view["bone_blob_count"] = len(blobs)

    # the maw: the largest dark throat region inside the body
    dlab, dn = ndimage.label(dark)
    maw = None
    if dn:
        sizes = ndimage.sum(dark, dlab, range(1, dn + 1))
        k = int(np.argmax(sizes)) + 1
        if sizes[k - 1] > 500:
            m = dlab == k
            mx0, my0, mx1, my1 = bbox(m)
            ys, xs = np.nonzero(m)
            maw = {"area_frac_of_body": round(float(m.sum()) / float(body.sum()), 4),
                   "w": round((mx1 - mx0) / H, 4), "h": round((my1 - my0) / H, 4),
                   "c": [round(float(xs.mean() - x0) / H, 4),
                         round(float(y1 - ys.mean()) / H, 4)]}
    view["maw_hole"] = maw

    # widest row and its height, plus ground contact run
    rows = []
    for y in range(y0, y1 + 1):
        xs = np.nonzero(body[y])[0]
        if len(xs):
            rows.append((y, xs.min(), xs.max()))
    widest = max(rows, key=lambda t: t[2] - t[1])
    view["widest_row_height_frac"] = round((y1 - widest[0]) / H, 4)
    view["widest_row_w"] = round((widest[2] - widest[1]) / H, 4)
    contact = body[int(y1 - 0.02 * H):y1 + 1]
    cols = contact.any(axis=0)
    runs, s = [], None
    for i, v in enumerate(cols):
        if v and s is None:
            s = i
        if not v and s is not None:
            if i - s > 4:
                runs.append([round((s - x0) / H, 4), round((i - x0) / H, 4)])
            s = None
    if s is not None:
        runs.append([round((s - x0) / H, 4), round((len(cols) - x0) / H, 4)])
    view["ground_contacts"] = runs

    out[name] = view
    overlays[name] = (path, body, bone, (x0, y0, x1, y1), blobs, maw)

# ------------------------------------------------------------------ overlay
tiles = []
for name, (path, body, bone, bb, blobs, maw) in overlays.items():
    im = Image.open(path).convert("RGB")
    x0, y0, x1, y1 = bb
    im = im.crop((max(0, x0 - 20), max(0, y0 - 20), x1 + 20, y1 + 20))
    d = ImageDraw.Draw(im)
    ox, oy = max(0, x0 - 20), max(0, y0 - 20)
    d.rectangle([x0 - ox, y0 - oy, x1 - ox, y1 - oy], outline=(220, 60, 50), width=3)
    for k, bl in enumerate(blobs[:20]):
        bx0, by0, bx1, by1 = bl["bbox"]
        d.rectangle([bx0 - ox, by0 - oy, bx1 - ox, by1 - oy], outline=(40, 130, 220), width=2)
        d.text((bx0 - ox, by0 - oy - 12), str(k), fill=(40, 130, 220))
    d.text((6, 6), name.upper(), fill=(20, 20, 20))
    im.thumbnail((520, 520), Image.LANCZOS)
    tiles.append(im)
sheet = Image.new("RGB", (sum(t.width for t in tiles) + 20, max(t.height for t in tiles)),
                  (245, 241, 234))
x = 0
for t in tiles:
    sheet.paste(t, (x, 0))
    x += t.width + 10
sheet.save("survey_sapscrap_overlay.png")
json.dump(out, open("survey_sapscrap.json", "w"), indent=1)

for name, v in out.items():
    print(f"== {name}: {v['w_px']}x{v['h_px']} px  W/H {v['w_over_h']}")
    print(f"   widest row at {v['widest_row_height_frac']} H, width {v['widest_row_w']} H")
    print(f"   bone blobs: {v['bone_blob_count']}  ground runs: {v['ground_contacts']}")
    if v["maw_hole"]:
        m = v["maw_hole"]
        print(f"   MAW hole: {m['w']} x {m['h']} H at {m['c']}, {m['area_frac_of_body']*100:.1f}% of body")
