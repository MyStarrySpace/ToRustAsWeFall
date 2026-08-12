"""Survey the arched Ferrule silhouette: isolate plates, mark landmark points.

Measurement comes before geometry. This writes a point table in NORMALISED
silhouette units (origin at the ground under the nose, +x rearward, +y up,
1.0 = total silhouette height) plus an annotated overlay to eyeball.
"""
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
       "reference-images/concept/fauna/silhouettes/"
       "ferrule-pyoverdine-structure-to-attack-silhouette-01.png")
OUT_OVERLAY = "survey_v3_overlay.png"
OUT_JSON = "survey_v3_points.json"

im = Image.open(SRC).convert("RGB")
a = np.asarray(im).astype(int)
H, W, _ = a.shape
r, g, b = a[..., 0], a[..., 1], a[..., 2]

black = a.max(axis=2) < 110
lime = (g > 100) & (b < 130) & (g >= r - 15) & (g > b + 45)
body = black | lime

# --- split the sheet into its three panels by empty column runs -------------
cols = body.any(axis=0)
runs, s = [], None
for x, v in enumerate(cols):
    if v and s is None:
        s = x
    if not v and s is not None:
        if x - s > 60:
            runs.append((s, x))
        s = None
if s is not None:
    runs.append((s, len(cols)))
print("panel column runs:", runs)
# the middle panel is the widest of the last two after the molecule diagram
panels = sorted(runs, key=lambda t: t[0])
px0, px1 = panels[1]
print("middle panel x:", px0, px1)

sub_body = body[:, px0:px1]
sub_black = black[:, px0:px1]
sub_lime = lime[:, px0:px1]
rows = sub_body.any(axis=1)
py0 = int(np.argmax(rows))
py1 = len(rows) - int(np.argmax(rows[::-1]))
sub_body = sub_body[py0:py1]
sub_black = sub_black[py0:py1]
sub_lime = sub_lime[py0:py1]
ph, pw = sub_body.shape
print("panel size:", pw, "x", ph, "  L/H =", round(pw / ph, 3))

# --- plates: the thin white seams separate the masses ----------------------
lab, n = ndimage.label(sub_black)
plates = []
for i in range(1, n + 1):
    m = lab == i
    area = int(m.sum())
    if area < 250:
        continue
    ys, xs = np.nonzero(m)
    plates.append({
        "id": len(plates),
        "area_px": area,
        "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        "centroid": [float(xs.mean()), float(ys.mean())],
        "w": int(xs.max() - xs.min() + 1),
        "h": int(ys.max() - ys.min() + 1),
    })
plates.sort(key=lambda p: p["centroid"][0])
for k, p in enumerate(plates):
    p["id"] = k
print(f"plates found: {len(plates)}")

# --- lime blobs -----------------------------------------------------------
llab, ln = ndimage.label(sub_lime)
limes = []
for i in range(1, ln + 1):
    m = llab == i
    if m.sum() < 40:
        continue
    ys, xs = np.nonzero(m)
    limes.append({
        "area_px": int(m.sum()),
        "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        "centroid": [float(xs.mean()), float(ys.mean())],
    })
limes.sort(key=lambda p: p["centroid"][0])
print(f"lime marks: {len(limes)}")

# --- ground line and contacts ---------------------------------------------
ground_y = ph - 1
contact = sub_body[int(ph * 0.965):, :].any(axis=0)
runs2, s = [], None
for x, v in enumerate(contact):
    if v and s is None:
        s = x
    if not v and s is not None:
        if x - s > 6:
            runs2.append((s, x))
        s = None
if s is not None:
    runs2.append((s, len(contact)))
print("ground contacts (x px):", runs2)

# --- the top profile: where the arch springs, peaks, and lands -------------
top = np.full(pw, np.nan)
bot = np.full(pw, np.nan)
for x in range(pw):
    ys = np.nonzero(sub_body[:, x])[0]
    if len(ys):
        top[x] = ys.min()
        bot[x] = ys.max()
valid = ~np.isnan(top)
apex_x = int(np.nanargmin(top))
apex_y = float(top[apex_x])
print(f"arch apex at x={apex_x} ({apex_x/pw:.3f} of length), y={apex_y:.0f} "
      f"(height {1 - apex_y/ph:.3f})")

# underside of the arch: the highest 'bottom' between the two ground contacts
if len(runs2) >= 2:
    g0 = runs2[0][1]
    g1 = runs2[-1][0]
    seg = bot[g0:g1]
    seg = np.where(np.isnan(seg), ph, seg)
    void_x = int(np.argmin(seg)) + g0
    void_y = float(seg[void_x - g0])
    print(f"arch underside high point x={void_x} ({void_x/pw:.3f}), "
          f"clearance {1 - void_y/ph:.3f} of H")
else:
    void_x, void_y = apex_x, ph


def norm(x, y):
    """px -> normalised: origin at ground under the nose, +x rearward, +y up."""
    return [round(x / ph, 4), round((ph - 1 - y) / ph, 4)]


landmarks = {}
nose_x = min(p["bbox"][0] for p in plates)
landmarks["nose_ground"] = norm(nose_x, ph - 1)
landmarks["arch_apex"] = norm(apex_x, apex_y)
landmarks["arch_void_peak"] = norm(void_x, void_y)
for i, (x0, x1) in enumerate(runs2):
    landmarks[f"ground_contact_{i}"] = {
        "x0": round(x0 / ph, 4), "x1": round(x1 / ph, 4),
        "width": round((x1 - x0) / ph, 4),
    }
for i, lm in enumerate(limes):
    x0, y0, x1, y1 = lm["bbox"]
    landmarks[f"lime_{i}"] = {
        "centroid": norm(*lm["centroid"]),
        "size": [round((x1 - x0) / ph, 4), round((y1 - y0) / ph, 4)],
        "tip": norm((x0 + x1) / 2, y1),
    }

# --- spine: the ordered stations a bone chain and the plate layout ride on
head_ids = [p["id"] for p in plates if p["centroid"][0] / ph < 0.60]
head_plates = [p for p in plates if p["id"] in head_ids]
wa = sum(p["area_px"] for p in head_plates)
head_c = [sum(p["centroid"][k] * p["area_px"] for p in head_plates) / wa for k in (0, 1)]
spine = [{"name": "head", "at": norm(*head_c),
          "area_frac": round(wa / (ph * ph), 5), "merged_plates": head_ids}]
NAMES = ["arch_rise", "arch_apex", "arch_fall", "haunch", "rear"]
rest = [p for p in plates if p["id"] not in head_ids]
for nm, p in zip(NAMES, rest):
    spine.append({"name": nm, "at": norm(*p["centroid"]),
                  "size": [round(p["w"] / ph, 4), round(p["h"] / ph, 4)],
                  "area_frac": round(p["area_px"] / (ph * ph), 5), "plate": p["id"]})
print("")
print("SPINE (build stations, head -> tail)")
for st in spine:
    print(f"  {st['name']:<10} at {st['at']}  area {st['area_frac']}")

survey = {
    "spine": spine,
    "source": SRC,
    "panel_px": {"x0": px0, "x1": px1, "y0": py0, "y1": py1, "w": pw, "h": ph},
    "length_over_height": round(pw / ph, 4),
    "units": "normalised by silhouette height; origin ground under the nose; +x rearward, +y up",
    "plates": [
        {
            "id": p["id"],
            "centroid": norm(*p["centroid"]),
            "size": [round(p["w"] / ph, 4), round(p["h"] / ph, 4)],
            "bbox_norm": [round(p["bbox"][0] / ph, 4), round((ph - 1 - p["bbox"][3]) / ph, 4),
                          round(p["bbox"][2] / ph, 4), round((ph - 1 - p["bbox"][1]) / ph, 4)],
            "area_frac": round(p["area_px"] / (ph * ph), 5),
        }
        for p in plates
    ],
    "landmarks": landmarks,
}
json.dump(survey, open(OUT_JSON, "w"), indent=1)

# --- annotated overlay ----------------------------------------------------
ov = im.crop((px0, py0, px1, py1)).convert("RGB")
ov = ov.resize((pw * 2, ph * 2), Image.NEAREST)
d = ImageDraw.Draw(ov)
S = 2
PAL = [(220, 60, 50), (40, 120, 220), (230, 150, 30), (150, 60, 200),
       (20, 160, 120), (200, 60, 140), (110, 130, 40), (60, 180, 220)]
for p in plates:
    c = PAL[p["id"] % len(PAL)]
    x0, y0, x1, y1 = [v * S for v in p["bbox"]]
    d.rectangle([x0, y0, x1, y1], outline=c, width=2)
    cx, cy = p["centroid"][0] * S, p["centroid"][1] * S
    d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=c)
    d.text((x0 + 3, y0 + 3), str(p["id"]), fill=c)
for i, lm in enumerate(limes):
    x0, y0, x1, y1 = [v * S for v in lm["bbox"]]
    d.rectangle([x0 - 2, y0 - 2, x1 + 2, y1 + 2], outline=(0, 200, 60), width=3)
    d.text((x0, y1 + 4), "L%d" % i, fill=(0, 160, 50))
d.line([0, (ph - 1) * S, pw * S, (ph - 1) * S], fill=(90, 90, 90), width=2)
for x0, x1 in runs2:
    d.line([x0 * S, (ph - 3) * S, x1 * S, (ph - 3) * S], fill=(0, 0, 0), width=6)
d.ellipse([apex_x * S - 8, apex_y * S - 8, apex_x * S + 8, apex_y * S + 8],
          outline=(255, 0, 0), width=3)
d.text((apex_x * S + 10, apex_y * S - 6), "apex", fill=(255, 0, 0))
d.ellipse([void_x * S - 8, void_y * S - 8, void_x * S + 8, void_y * S + 8],
          outline=(0, 90, 255), width=3)
d.text((void_x * S + 10, void_y * S - 6), "arch void", fill=(0, 90, 255))
ov.save(OUT_OVERLAY)
print("wrote", OUT_OVERLAY, "and", OUT_JSON)

print("\nplate table (normalised, origin ground-under-nose, +x rearward, +y up)")
print(f"{'id':>3} {'cx':>7} {'cy':>7} {'w':>6} {'h':>6} {'area':>7}")
for p in survey["plates"]:
    print(f"{p['id']:>3} {p['centroid'][0]:>7.3f} {p['centroid'][1]:>7.3f} "
          f"{p['size'][0]:>6.3f} {p['size'][1]:>6.3f} {p['area_frac']:>7.4f}")
