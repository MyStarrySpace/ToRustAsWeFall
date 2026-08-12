# BlockBench-style pixel-perfect unwrap + the hand-painted grammar painter.
#
# Each Builder primitive is a PAINT GROUP laid out contiguously, exactly the way
# BlockBench unfolds a cuboid:
#
#               [   top W*D   ]
#   [-x D*H] [ -y W*H ] [+x D*H] [ +y W*H ]      (one continuous side strip)
#               [ bottom W*D  ]
#
# Prisms unwrap as one wrap-around side strip + cap polygons; annuli as four
# strips (outer/inner walls, front/back rings). Every face maps to an INTEGER
# pixel rect at the density (32 px/m) — corners sit on texel boundaries, so the
# texture is pixel-perfect and paint flows across a part's edges. After painting,
# island borders are DILATED into the gutters (edge bleed) so NEAREST sampling at
# island boundaries can never pick up background.
#
# The painter reproduces the artist's grammar (measured from the Aster room
# atlas, desk, and the Peris couch/bench sheets): flat fills from a fixed 4-shade
# ramp per material, 1px dark outlines with rounded corners on large faces,
# bevel light (top) / shade (bottom) on tall faces, painted seams / wood grain /
# weave bands / speckle per material family, and emissive only where a part
# declares it.

import bpy
import json
import math
import zlib
import numpy as np

from .palette import (PARTS, PART_FAMILY, EMIT_STRENGTH, DETAIL_PAINTERS,
                      CARD_PAINTERS, DETAIL_NONE, DETAIL_SCREEN)
from .atlas import shade, make_atlas_material, DEFAULT_PX_PER_M

# Texels of separation between islands that are NOT adjacent in the mesh. Two
# texels survives one mip level; one survives only bilinear sampling. Applied
# between packed groups AND between the islands inside a group — a prism's cap
# meets its side strip along a single ring, not across the strip's whole top edge,
# so laying them flush bleeds colour between faces that never touch.
GUTTER = 2


def _h(*keys):
    """Stable deterministic hash for paint variation (never process-salted)."""
    return zlib.crc32("|".join(str(k) for k in keys).encode())


def _px(v, d):
    return max(1, int(round(v * d)))


# ------------------------------------------------------------------ layout ----
def _layout_group(g, d):
    """Returns (w, h, faces) where faces = list of
    {face: index, rect: (x, y, w, h), uv: {corner_key: (u_px, v_px)}, role}
    in group-local pixel space (y up)."""
    kind = g["kind"]
    out = []
    if kind == "box":
        sx, sy, sz = g["size"]
        W, D, H = _px(sx, d), _px(sy, d), _px(sz, d)
        strip_y = D
        xoff = {"-x": 0, "-y": D, "+x": D + W, "+y": D + W + D}
        widths = {"-x": D, "-y": W, "+x": D, "+y": W}
        # perimeter walk (-x -> -y -> +x -> +y) seen from outside; u follows the
        # walk so paint wraps around the box; v follows world up
        udir = {  # face -> (axis, sign) giving u from the corner key
            "-x": (1, -1), "-y": (0, 1), "+x": (1, 1), "+y": (0, -1)}
        for name in ("-x", "-y", "+x", "+y"):
            if name not in g["faces"]:
                continue
            x0 = xoff[name]
            w = widths[name]
            axis, sign = udir[name]
            uv = {}
            for key_dx in (-1, 1):
                for key_dy in (-1, 1):
                    for key_dz in (-1, 1):
                        key = (key_dx, key_dy, key_dz)
                        u = (0 if (key[axis] * sign) < 0 else w)
                        v = 0 if key_dz < 0 else H
                        uv[key] = (x0 + u, strip_y + v)
            out.append({"face": g["faces"][name], "rect": (x0, strip_y, w, H),
                        "uv": uv, "role": "side", "name": name})
        if "top" in g["faces"]:
            uv = {}
            for key_dx in (-1, 1):
                for key_dy in (-1, 1):
                    for key_dz in (-1, 1):
                        uv[(key_dx, key_dy, key_dz)] = (
                            D + (0 if key_dx < 0 else W),
                            strip_y + H + (0 if key_dy < 0 else D))
            out.append({"face": g["faces"]["top"], "rect": (D, strip_y + H, W, D),
                        "uv": uv, "role": "top", "name": "top"})
        if "bottom" in g["faces"]:
            uv = {}
            for key_dx in (-1, 1):
                for key_dy in (-1, 1):
                    for key_dz in (-1, 1):
                        uv[(key_dx, key_dy, key_dz)] = (
                            D + (0 if key_dx < 0 else W),
                            (D if key_dy < 0 else 0))
            out.append({"face": g["faces"]["bottom"], "rect": (D, 0, W, D),
                        "uv": uv, "role": "bottom", "name": "bottom"})
        return (2 * D + 2 * W, D + H + D, out)

    if kind == "prism":
        sides = g["sides"]
        H = _px(g["height"], d)
        r_mid = (g["r_top"] + g["r_bot"]) * 0.5
        seg_w = max(1, int(round(2.0 * r_mid * math.sin(math.pi / sides) * d)))
        strip_w = seg_w * sides
        cap_r = _px(max(g["r_top"], g["r_bot"]), d)
        cap_size = 2 * cap_r
        ncaps = (1 if g["cap_top"] >= 0 else 0) + (1 if g["cap_bottom"] >= 0 else 0)
        total_w = max(strip_w, ncaps * cap_size + (GUTTER if ncaps == 2 else 0))
        # side strip along the bottom, caps above it
        for i, fidx in enumerate(g["side_faces"]):
            uv = {}
            j = (i + 1) % sides
            uv[("bot", i)] = (i * seg_w, 0)
            uv[("bot", j)] = ((i + 1) * seg_w, 0)
            uv[("top", j)] = ((i + 1) * seg_w, H)
            uv[("top", i)] = (i * seg_w, H)
            out.append({"face": fidx, "rect": (i * seg_w, 0, seg_w, H),
                        "uv": uv, "role": "strip_seg", "seg": i, "segs": sides})
        # A cap is NOT mesh-adjacent to the middle of the side strip — it meets it
        # along one ring only — so laying it flush against the strip makes texels
        # bleed between faces that never touch. Unfolded BOX crosses are the
        # opposite case (their neighbours ARE adjacent across a real edge, and the
        # bleed hides the seam), which is why the gutter belongs here and not there.
        cap_y = H + GUTTER
        cap_x = 0
        for cap_name, ring in (("cap_top", "top"), ("cap_bottom", "bot")):
            fidx = g[cap_name]
            if fidx < 0:
                continue
            uv = {}
            for i in range(sides):
                a = 2 * math.pi * i / sides
                uv[(ring, i)] = (cap_x + cap_r + int(round(cap_r * math.cos(a))),
                                 cap_y + cap_r + int(round(cap_r * math.sin(a))))
            out.append({"face": fidx, "rect": (cap_x, cap_y, cap_size, cap_size),
                        "uv": uv, "role": "cap", "r": cap_r})
            cap_x += cap_size + GUTTER
        h = H + (cap_size + GUTTER
                 if any(g[c] >= 0 for c in ("cap_top", "cap_bottom")) else 0)
        return (total_w, h, out)

    if kind == "tube":
        # A swept tube unwraps like a prism's side strip with more rows: one
        # column per side, one row per span between stations. The seam is handled
        # the way the prism handles it — the wrapping column's far edge is keyed
        # to side 0 at full width, and because UVs are per-LOOP the shared
        # vertices carry both values without tearing.
        sides = g["sides"]
        rows = g["rows"]
        radii = g["radii"]
        r_mid = sum(radii) / float(len(radii))
        seg_w = max(1, int(round(2.0 * r_mid * math.sin(math.pi / sides) * d)))
        strip_w = seg_w * sides
        v = [0]
        for L in g["seg_len"]:
            v.append(v[-1] + _px(L, d))
        H = v[-1]
        cap_r = _px(max(radii), d)
        cap_size = 2 * cap_r
        ncaps = (1 if g["cap_start"] >= 0 else 0) + (1 if g["cap_end"] >= 0 else 0)
        total_w = max(strip_w, ncaps * cap_size + (GUTTER if ncaps == 2 else 0))
        for r in range(rows):
            for k, fidx in enumerate(g["side_faces"][r]):
                if fidx < 0:
                    continue        # a graft cut this seat; the row keeps its shape
                j = (k + 1) % sides
                uv = {
                    ("ring", r, k): (k * seg_w, v[r]),
                    ("ring", r, j): ((k + 1) * seg_w, v[r]),
                    ("ring", r + 1, j): ((k + 1) * seg_w, v[r + 1]),
                    ("ring", r + 1, k): (k * seg_w, v[r + 1]),
                }
                out.append({"face": fidx,
                            "rect": (k * seg_w, v[r], seg_w, v[r + 1] - v[r]),
                            "uv": uv, "role": "strip_seg", "seg": k,
                            "segs": sides})
        cap_y = H + GUTTER
        cap_x = 0
        for cap_name, ring_i in (("cap_start", 0), ("cap_end", rows)):
            fidx = g[cap_name]
            if fidx < 0:
                continue
            uv = {}
            for i in range(sides):
                a = 2 * math.pi * i / sides
                uv[("ring", ring_i, i)] = (
                    cap_x + cap_r + int(round(cap_r * math.cos(a))),
                    cap_y + cap_r + int(round(cap_r * math.sin(a))))
            out.append({"face": fidx, "rect": (cap_x, cap_y, cap_size, cap_size),
                        "uv": uv, "role": "cap", "r": cap_r})
            cap_x += cap_size + GUTTER
        h = H + (cap_size + GUTTER if ncaps else 0)
        return (total_w, h, out)

    if kind == "annulus":
        sides = g["sides"]
        rows = []
        y = 0
        specs = [("outer", g["r_out"], _px(g["depth"], d)),
                 ("inner", g["r_in"], _px(g["depth"], d)),
                 ("front", (g["r_out"] + g["r_in"]) * 0.5, _px(g["r_out"] - g["r_in"], d)),
                 ("back", (g["r_out"] + g["r_in"]) * 0.5, _px(g["r_out"] - g["r_in"], d))]
        ring_pairs = {"outer": ("of", "ob"), "inner": ("ib", "if"),
                      "front": ("if", "of"), "back": ("ob", "ib")}
        width = 0
        for strip_name, radius, hh in specs:
            seg_w = max(1, int(round(2.0 * radius * math.sin(math.pi / sides) * d)))
            near, far = ring_pairs[strip_name]
            for i, fidx in enumerate(g["strips"][strip_name]):
                j = (i + 1) % sides
                uv = {(near, i): (i * seg_w, y), (near, j): ((i + 1) * seg_w, y),
                      (far, j): ((i + 1) * seg_w, y + hh), (far, i): (i * seg_w, y + hh)}
                out.append({"face": fidx, "rect": (i * seg_w, y, seg_w, hh),
                            "uv": uv, "role": "strip_seg", "seg": i, "segs": sides})
            width = max(width, seg_w * sides)
            y += hh + GUTTER          # each ring strip is its own island
        return (width, y, out)

    if kind == "card":
        # A card is its own island, laid out 1:1 with the texture it wears — the
        # pixel art IS the form, so the UV must be an honest rectangle at exactly
        # px_per_m or the drawn grate/leaf comes out stretched. A SEGMENTED card
        # (one that will be rigged, so it can bend) is still ONE image: the strips
        # are mesh-adjacent, so they tile the same rectangle with no gutter.
        w = max(1, _px(g["size"][0], d))
        h = max(1, _px(g["size"][1], d))
        segs = int(g.get("segments", 1))
        face_ids = g.get("faces", [g["face"]])
        for i, fidx in enumerate(face_ids):
            v0 = int(round(h * i / float(segs)))
            v1 = int(round(h * (i + 1) / float(segs)))
            uv = {(i, 0): (0, v0), (i, 1): (w, v0),
                  (i + 1, 1): (w, v1), (i + 1, 0): (0, v1)}
            out.append({"face": fidx, "rect": (0, v0, w, max(1, v1 - v0)),
                        "uv": uv, "role": "card"})
        return (w, h, out)

    if kind == "disc":
        R = _px(g["r"], d)
        uv = {}
        sides = len(g["corners"])
        for i in range(sides):
            a = 2 * math.pi * i / sides
            uv[i] = (R + int(round(R * math.cos(a))), R + int(round(R * math.sin(a))))
        out.append({"face": g["face"], "rect": (0, 0, 2 * R, 2 * R),
                    "uv": uv, "role": "cap", "r": R})
        return (2 * R, 2 * R, out)

    raise ValueError("unknown group kind %s" % kind)


def unwrap_grouped(ob, atlas_px, px_per_m=DEFAULT_PX_PER_M):
    """Lay every paint group out contiguously and shelf-pack the groups.
    Writes pixel-boundary UVs. Returns the placed groups (raises on overflow)."""
    groups = json.loads(ob["paint_groups"])
    placed = []
    for g in groups:
        w, h, faces = _layout_group(g, px_per_m)
        placed.append({"g": g, "w": w, "h": h, "faces": faces})
    placed.sort(key=lambda p: -p["h"])
    x = y = shelf_h = 0
    for p in placed:
        pw, ph = p["w"] + GUTTER, p["h"] + GUTTER
        if pw > atlas_px - GUTTER:
            raise RuntimeError("atlas overflow")   # single group wider than the sheet
        if x + pw > atlas_px - GUTTER:
            x = 0
            y += shelf_h
            shelf_h = 0
        if y + ph > atlas_px - GUTTER:
            raise RuntimeError("atlas overflow")
        p["ox"], p["oy"] = x + GUTTER, y + GUTTER
        x += pw
        shelf_h = max(shelf_h, ph)

    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active.data
    for p in placed:
        corners = {int(k): (tuple(v) if isinstance(v, list) else v)
                   for k, v in p["g"]["corners"].items()}
        for fspec in p["faces"]:
            poly = me.polygons[fspec["face"]]
            for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
                vi = me.loops[li].vertex_index
                key = corners[vi]
                u_px, v_px = fspec["uv"][key]
                uvl[li].uv = ((p["ox"] + u_px) / atlas_px, (p["oy"] + v_px) / atlas_px)
    return placed


# ----------------------------------------------------------------- painting ----
def _ramp(base):
    return {
        "outline": shade(base, 0.55),
        "dark": shade(base, 0.84),
        "base": base,
        "light": shade(base, 1.14),
        "hi": shade(base, 1.28),
    }

WOODS = {"wood", "wood_light", "stand_wood", "art_frame"}
FABRICS = {"chair_pink", "cushion", "plush_peach", "plush_blue"}
PANELS = {"kiosk_body", "dark", "mono_wall", "mono_wall_lo", "mono_trim", "portal_frame"}
SPECKLED = {"rug_field", "mono_floor"}


def _rounded_outline(a, x0, y0, w, h, color):
    """1px outline with cut corners (the rounded-rect look) for faces >= 8px."""
    r = 1 if min(w, h) >= 8 else 0
    a[y0, x0 + r:x0 + w - r] = color
    a[y0 + h - 1, x0 + r:x0 + w - r] = color
    a[y0 + r:y0 + h - r, x0] = color
    a[y0 + r:y0 + h - r, x0 + w - 1] = color
    if r:
        for cx, cy in ((x0 + 1, y0 + 1), (x0 + w - 2, y0 + 1),
                       (x0 + 1, y0 + h - 2), (x0 + w - 2, y0 + h - 2)):
            a[cy, cx] = color


def _steel_lift(c, t, target=(0.62, 0.66, 0.72)):
    """Worn-through metal catch-light: visible on ANY base (the lift law)."""
    return tuple(v + (tv - v) * t for v, tv in zip(c[:3], target))


def _worn_outline(a, x0, y0, w, h, ramp, rnd, role):
    """EDGEWEAR grammar: every box border is a CONVEX edge (butting faces are
    never created), so borders wear — the dark outline stays the seam read,
    but the exposed edges collect deterministic CHIPS of worn-through metal
    (steel catch-light), densest on the TOP edge (v-up: the top border is row
    y0+h-1) and the upper corners, sparse on the verticals. The BOTTOM edge
    doubles dark instead — contact grime grounds the shape. Chips are 1-2px
    posterized nicks, never a uniform stroke."""
    _rounded_outline(a, x0, y0, w, h, ramp["outline"])
    top_row = y0 + h - 1
    chip_hi = _steel_lift(ramp["base"], 0.55)
    chip_lo = _steel_lift(ramp["base"], 0.3)
    if role != "bottom" and w >= 8:
        for k in range(max(1, w // 7)):
            cx = x0 + 1 + (_h(rnd, 21, k) % (w - 2))
            ln = 1 + (_h(rnd, 22, k) % 2)
            a[top_row, cx:min(x0 + w - 1, cx + ln)] = chip_hi
            if _h(rnd, 23, k) % 3 == 0 and h >= 6:
                a[top_row - 1, cx] = chip_lo
    if h >= 10:
        for edge_x in (x0, x0 + w - 1):
            for k in range(max(1, h // 9)):
                cy = y0 + h // 2 + (_h(rnd, 24, k, edge_x) % max(1, h // 2 - 1))
                a[cy, edge_x] = chip_lo
    if w >= 8 and h >= 8:
        for cx, cy in ((x0 + 1, top_row - 1), (x0 + w - 2, top_row - 1)):
            if _h(rnd, 25, cx) % 2 == 0:
                a[cy, cx] = chip_hi
    if role != "top" and w >= 6 and h >= 6:
        a[y0 + 1, x0 + 1:x0 + w - 1] = shade(ramp["outline"], 0.85)



# ------------------------------------------------------- contact seams ----
# A shape resting on or crossing another face leaves a CONTACT SEAM: the dark
# outline of its footprint plus a step of contact grime. Geometry-derived and
# deterministic — the painter reads each group's center+size (world AABBs) and
# projects footprints into face pixels through the same corner-UV mapping the
# unwrap wrote, so orientation and mirroring are always correct.
_FACE_AXIS = {"top": (2, 1), "bottom": (2, -1),
              "+x": (0, 1), "-x": (0, -1), "+y": (1, 1), "-y": (1, -1)}
_CONTACT_EPS = 0.022


def _group_aabb(g):
    c = g.get("center")
    if c is None:
        return None
    k = g["kind"]
    if k == "box":
        h = [g["size"][0] * 0.5, g["size"][1] * 0.5, g["size"][2] * 0.5]
    elif k == "prism":
        r = max(g["r_top"], g["r_bot"])
        h = [r, r, g["height"] * 0.5]
    elif k == "tube":
        r = max(g["radii"])
        span = sum(g["seg_len"]) * 0.5
        h = [max(r, span)] * 3
    elif k == "annulus":
        h = [g["r_out"], g["depth"] * 0.5, g["r_out"]]
    elif k == "disc":
        h = [g["r"], g["r"], 0.012]
    elif k == "card":
        w, ht = g["size"][0] * 0.5, g["size"][1] * 0.5
        h = [w, 0.006, ht] if g.get("axis", 'Y') != 'Z' else [w, ht, 0.006]
    else:
        return None
    return ([c[i] - h[i] for i in range(3)], [c[i] + h[i] for i in range(3)])


def _face_contacts(g, face_name, all_aabbs, self_idx, d):
    """Contact rects for one BOX face, in group-local pixel space. Each entry:
    (px0, py0, px1, py1, edges, resting) where edges flags which seam edges are
    the other shape's REAL boundary (a clipped edge paints nothing)."""
    if face_name not in _FACE_AXIS or "center" not in g:
        return []
    n, sgn = _FACE_AXIS[face_name]
    axes = [a for a in (0, 1, 2) if a != n]
    c, size = g["center"], g["size"]
    half = [size[0] * 0.5, size[1] * 0.5, size[2] * 0.5]
    plane = c[n] + sgn * half[n]
    # corner-UV bilinear: keys with key[n] == sgn
    def key_for(fa, fb):
        key = [0, 0, 0]
        key[n] = sgn
        key[axes[0]] = -1 if fa == 0 else 1
        key[axes[1]] = -1 if fb == 0 else 1
        return tuple(key)
    out = []
    for idx, aabb in all_aabbs:
        if idx == self_idx or aabb is None:
            continue
        lo, hi = aabb
        if lo[n] > plane + _CONTACT_EPS or hi[n] < plane - _CONTACT_EPS:
            continue
        fr, ed = [], []
        ok = True
        for a in axes:
            a0 = max(lo[a], c[a] - half[a])
            a1 = min(hi[a], c[a] + half[a])
            if a1 - a0 < 0.02:
                ok = False
                break
            fr.append(((a0 - (c[a] - half[a])) / (2 * half[a]),
                       (a1 - (c[a] - half[a])) / (2 * half[a])))
            ed.append((lo[a] > c[a] - half[a] + 0.01,
                       hi[a] < c[a] + half[a] - 0.01))
        if not ok:
            continue
        area = (fr[0][1] - fr[0][0]) * (fr[1][1] - fr[1][0])
        if area > 0.92 or area <= 0.0:
            continue
        # the shape RESTS on this face if it lies on the outward side of the
        # plane (a strap crossing THROUGH gets outline only, no grime fill)
        resting = (lo[n] >= plane - _CONTACT_EPS) if sgn > 0             else (hi[n] <= plane + _CONTACT_EPS)
        return_uv = g["_uvmap"]
        def bl(fa, fb):
            p00 = return_uv[key_for(0, 0)]
            p10 = return_uv[key_for(1, 0)]
            p01 = return_uv[key_for(0, 1)]
            p11 = return_uv[key_for(1, 1)]
            x = (p00[0] * (1 - fa) * (1 - fb) + p10[0] * fa * (1 - fb)
                 + p01[0] * (1 - fa) * fb + p11[0] * fa * fb)
            y = (p00[1] * (1 - fa) * (1 - fb) + p10[1] * fa * (1 - fb)
                 + p01[1] * (1 - fa) * fb + p11[1] * fa * fb)
            return x, y
        pa = bl(fr[0][0], fr[1][0])
        pb = bl(fr[0][1], fr[1][1])
        px0, px1 = sorted((pa[0], pb[0]))
        py0, py1 = sorted((pa[1], pb[1]))
        # edge realness must ride the SAME mapping (mirrors swap lo/hi): probe
        # which pixel side each fraction-boundary landed on
        flipped_x = bl(fr[0][0], fr[1][0])[0] > bl(fr[0][1], fr[1][0])[0]
        flipped_y = bl(fr[0][0], fr[1][0])[1] > bl(fr[0][0], fr[1][1])[1]
        ex = (ed[0][1], ed[0][0]) if flipped_x else ed[0]
        ey = (ed[1][1], ed[1][0]) if flipped_y else ed[1]
        out.append((int(round(px0)), int(round(py0)),
                    int(round(px1)), int(round(py1)),
                    (ex[0], ex[1], ey[0], ey[1]), resting))
    return out


def _paint_contacts(a, x0, y0, w, h, ramp, contacts):
    for (cx0, cy0, cx1, cy1, edges, resting) in contacts:
        gx0 = max(x0, x0 + cx0)
        gx1 = min(x0 + w, x0 + cx1)
        gy0 = max(y0, y0 + cy0)
        gy1 = min(y0 + h, y0 + cy1)
        if gx1 - gx0 < 1 or gy1 - gy0 < 1:
            continue
        if resting and gx1 - gx0 > 2 and gy1 - gy0 > 2:
            a[gy0:gy1, gx0:gx1] = shade(ramp["base"], 0.93)
        seam = shade(ramp["outline"], 0.92)
        lo_x_real, hi_x_real, lo_y_real, hi_y_real = edges
        if lo_x_real and gx0 > x0:
            a[gy0:gy1, gx0] = seam
        if hi_x_real and gx1 - 1 < x0 + w - 1:
            a[gy0:gy1, gx1 - 1] = seam
        if lo_y_real and gy0 > y0:
            a[gy0, gx0:gx1] = seam
        if hi_y_real and gy1 - 1 < y0 + h - 1:
            a[gy1 - 1, gx0:gx1] = seam

def _paint_face(a, part_name, ramp, fspec, gx, gy, seed, contacts=()):
    x0, y0 = gx + fspec["rect"][0], gy + fspec["rect"][1]
    w, h = fspec["rect"][2], fspec["rect"][3]
    if w <= 0 or h <= 0:
        return
    fam = PART_FAMILY.get(part_name)
    role = fspec.get("role", "side")
    fill = ramp["base"]
    if role == "top":
        fill = ramp["light"]
    elif role == "bottom":
        fill = ramp["dark"]
    a[y0:y0 + h, x0:x0 + w] = fill

    big = w > 4 and h > 4
    if role == "cap":
        # circular cap: fill disc, outline ring
        r = fspec["r"]
        yy, xx = np.ogrid[:h, :w]
        dist2 = (yy - r) ** 2 + (xx - r) ** 2
        disc = dist2 <= r * r
        region = a[y0:y0 + h, x0:x0 + w]
        region[...] = ramp["base"]
        region[~disc] = fill  # harmless; bleed handles gutter
        ring = (dist2 <= r * r) & (dist2 >= (r - 1.3) ** 2)
        region[ring] = ramp["outline"]
        return

    if role == "strip_seg":
        # contiguous wrap strip: outline only the strip's top/bottom rows, never
        # per-segment verticals (a cylinder must not get bars)
        #
        # AND ONLY IF THERE IS A MIDDLE LEFT. A strip three texels tall or shorter
        # spends every row it has on the two outline rows, so the whole face comes
        # out the outline colour — a small feature does not read as outlined, it
        # reads as BLACK. That is what turned the Gasafoetida's resin seals into
        # holes bored down its pods, which is the one state a sealed cone must not
        # be in. Short faces keep their base colour and lose the silhouette line,
        # which at that size was never legible anyway.
        if h >= 4:
            a[y0, x0:x0 + w] = ramp["outline"]
            a[y0 + h - 1, x0:x0 + w] = ramp["outline"]
        if fspec["seg"] == 0:
            a[y0:y0 + h, x0] = ramp["outline"]
        if fspec["seg"] == fspec["segs"] - 1:
            a[y0:y0 + h, x0 + w - 1] = ramp["outline"]
        if part_name == "basket" and h > 4:
            for row in range(y0 + 2, y0 + h - 2, 2):
                a[row, x0:x0 + w] = ramp["dark"]
        return

    if big:
        rnd_w = _h(seed, x0, y0, 9)
        _worn_outline(a, x0, y0, w, h, ramp, rnd_w, role)
        if role == "side" and h >= 6:
            a[y0 + h - 2, x0 + 1:x0 + w - 1] = ramp["light"]   # top bevel (v up)
            a[y0 + 1, x0 + 1:x0 + w - 1] = ramp["dark"]        # bottom shade
            if h >= 12:
                # grounding band: one extra posterized dark step at the base —
                # the shape SITS instead of floating (bring-out-the-form law)
                a[y0 + 2, x0 + 1:x0 + w - 1] = shade(ramp["base"], 0.9)

    # material families (deterministic variation)
    rnd = _h(seed, x0, y0)
    if (part_name in WOODS or fam == "wood") and w >= 10 and h >= 6:
        for k in range(1 + (w * h) // 260):
            gy_ = y0 + 2 + (_h(rnd, k, 1) % max(1, h - 4))
            gx_ = x0 + 2 + (_h(rnd, k, 2) % max(1, w // 2))
            gl = 3 + (_h(rnd, k, 3) % max(2, w // 3))
            a[gy_, gx_:min(x0 + w - 2, gx_ + gl)] = ramp["dark"]
    elif (part_name in FABRICS or fam == "fabric") and w >= 8 and h >= 8:
        crease = y0 + h // 3
        a[crease, x0 + 2:x0 + w - 2] = ramp["dark"]
    elif (part_name in PANELS or fam == "panel") and w >= 12 and h >= 8:
        seam = x0 + w // 3 + (_h(rnd, 7) % max(1, w // 4))
        a[y0 + 2:y0 + h - 2, seam] = ramp["dark"]
        a[y0 + h - 3, seam - 1] = ramp["light"]
    elif part_name == "ceramic" and w >= 6 and h >= 6:
        a[y0 + 2:y0 + h - 2, x0 + 2] = ramp["hi"]
    if (part_name in SPECKLED or fam == "speckled") and w >= 10 and h >= 10:
        for k in range((w * h) // 40):
            sy_ = y0 + 2 + (_h(rnd, k, 4) % (h - 4))
            sx_ = x0 + 2 + (_h(rnd, k, 5) % (w - 4))
            a[sy_, sx_] = ramp["dark"] if (_h(rnd, k, 6) & 1) else ramp["light"]
    if contacts and w > 3 and h > 3:
        _paint_contacts(a, x0, y0, w, h, ramp, contacts)


def _bleed(alb, cov, passes=2):
    """Dilate island edge colors into uncovered gutter texels."""
    for _ in range(passes):
        uncovered = ~cov
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            src_cov = np.roll(cov, (dy, dx), (0, 1))
            src = np.roll(alb, (dy, dx), (0, 1))
            take = uncovered & src_cov
            alb[take] = src[take]
            cov = cov | take
            uncovered = uncovered & ~take
    return cov


def _card_emitted(emi, p):
    """True when anything inside this card's rect glows."""
    x0, y0, w, h = p["ox"], p["oy"], p["w"], p["h"]
    return bool(emi[y0:y0 + h, x0:x0 + w, :3].any())


def _paint_card(alb, emi, cov, p, g, part, part_name, px_per_m):
    """Paint one card's whole rect. The painter owns RGBA — its transparent texels
    ARE the form — and may write its own emissive plane for a card that glows along
    only part of itself (a fern whose veins are the light and whose tissue is not).
    The solid-face grammar (seam borders, edgewear, contact shadows) is deliberately
    skipped: every one of those assumes a solid face."""
    x0, y0 = p["ox"], p["oy"]
    w, h = p["w"], p["h"]
    art_fn = CARD_PAINTERS.get(g.get("art", 0))
    tile = np.zeros((h, w, 4), dtype=np.float32)
    tile[:, :, :3] = part["rgb"]
    tile[:, :, 3] = 1.0
    etile = np.zeros((h, w, 3), dtype=np.float32)
    if art_fn is not None:
        art_fn(tile, {"pw": w, "ph": h, "part": part_name, "rgb": part["rgb"],
                      "axis": g.get("axis", 'Y'), "size": g.get("size"),
                      "emit": etile}, px_per_m)
    alb[y0:y0 + h, x0:x0 + w] = tile
    cov[y0:y0 + h, x0:x0 + w] = True
    if not etile.any() and "emit" in part:
        etile[:, :] = part["emit"]
    etile *= tile[:, :, 3:4]                 # a hole emits nothing
    emi[y0:y0 + h, x0:x0 + w, :3] = etile


def paint_grouped(placed, atlas_px, path_albedo, path_emissive,
                  px_per_m=DEFAULT_PX_PER_M):
    alb = np.zeros((atlas_px, atlas_px, 4), dtype=np.float32)
    alb[:, :, :3] = (0.45, 0.38, 0.32)
    alb[:, :, 3] = 1.0
    emi = np.zeros((atlas_px, atlas_px, 4), dtype=np.float32)
    emi[:, :, 3] = 1.0
    cov = np.zeros((atlas_px, atlas_px), dtype=bool)
    rgb = alb[:, :, :3]

    has_emit = False
    all_aabbs = [(i, _group_aabb(p["g"])) for i, p in enumerate(placed)]
    for self_idx, p in enumerate(placed):
        g = p["g"]
        part_name = g["part"]
        part = PARTS[part_name]
        if g["kind"] == "card":
            # A card is painted ONCE as a whole image, whatever it is segmented
            # into: the art is authored for the card, and its strips only exist so
            # a bone chain has something to bend.
            _paint_card(alb, emi, cov, p, g, part, part_name, px_per_m)
            if "emit" in part or CARD_PAINTERS.get(g.get("art", 0)) is not None:
                has_emit = has_emit or _card_emitted(emi, p)
            continue
        ramp = _ramp(part["rgb"])
        seed = _h(part_name, p["ox"], p["oy"])
        for fspec in p["faces"]:
            x0, y0 = p["ox"] + fspec["rect"][0], p["oy"] + fspec["rect"][1]
            w, h = fspec["rect"][2], fspec["rect"][3]
            if x0 + w > atlas_px or y0 + h > atlas_px:
                raise RuntimeError(
                    "face rect escapes atlas: part=%s kind=%s role=%s rect=%s group=(%d,%d %dx%d) atlas=%d"
                    % (part_name, g["kind"], fspec.get("role"), fspec["rect"],
                       p["ox"], p["oy"], p["w"], p["h"], atlas_px))
            contacts = ()
            if g["kind"] == "box" and "center" in g and fspec.get("name"):
                g["_uvmap"] = fspec["uv"]
                contacts = _face_contacts(g, fspec["name"], all_aabbs, self_idx, px_per_m)
            _paint_face(rgb, part_name, ramp, fspec, p["ox"], p["oy"], seed, contacts)
            det = g.get("detail", DETAIL_NONE)
            painter = DETAIL_PAINTERS.get(det)
            if painter is not None and w > 2 and h > 2:
                tile = rgb[y0:y0 + h, x0:x0 + w].copy()
                mask = np.ones((h, w), dtype=bool)
                # The painter gets the REAL texel density (features authored in
                # metres must land at the piece's px_per_m, not the default) and
                # enough identity (group origin, segment index) to vary between
                # same-sized faces instead of painting clones.
                role = fspec.get("role")
                painter(tile, mask, part["rgb"],
                        {"pw": w, "ph": h, "name": fspec.get("name"),
                         "role": role, "seg": fspec.get("seg"),
                         "segs": fspec.get("segs"),
                         "ox": p["ox"], "oy": p["oy"]}, px_per_m)
                rgb[y0:y0 + h, x0:x0 + w] = tile
                # Re-stamp the house outline grammar the painter overwrote: every
                # face keeps its 1px silhouette so painted pieces stay in the
                # hand-painted couch/bench language.
                if role == "strip_seg":
                    # same height guard as the base pass: a strip with no middle
                    # row left is not outlined, it is erased
                    if h >= 4:
                        rgb[y0, x0:x0 + w] = ramp["outline"]
                        rgb[y0 + h - 1, x0:x0 + w] = ramp["outline"]
                    if w >= 4 and fspec["seg"] == 0:
                        rgb[y0:y0 + h, x0] = ramp["outline"]
                    if w >= 4 and fspec["seg"] == fspec["segs"] - 1:
                        rgb[y0:y0 + h, x0 + w - 1] = ramp["outline"]
                elif role != "cap" and w > 4 and h > 4:
                    _rounded_outline(rgb, x0, y0, w, h, ramp["outline"])
            cov[y0:y0 + h, x0:x0 + w] = True
            if "emit" in part:
                has_emit = True
                etile = np.zeros((h, w, 3), dtype=np.float32)
                etile[:, :] = part["emit"]
                if det == DETAIL_SCREEN:
                    for row in range(1, h - 1, 3):
                        etile[row, 1:-1] = shade(part["emit"], 0.4)
                emi[y0:y0 + h, x0:x0 + w, :3] = etile

    _bleed(rgb, cov.copy())

    def save(arr, path, name):
        img = bpy.data.images.new(name, atlas_px, atlas_px, alpha=True)
        img.pixels[:] = arr.ravel()
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return img
    import os
    img_a = save(alb, path_albedo, os.path.splitext(os.path.basename(path_albedo))[0])
    img_e = None
    if has_emit and path_emissive is not None:
        img_e = save(emi, path_emissive, os.path.splitext(os.path.basename(path_emissive))[0])
    return img_a, img_e


def texture_object_grouped(ob, tex_dir, px_per_m=DEFAULT_PX_PER_M, painted_dir=None):
    """The grouped (BlockBench-style) version of texture_object; used whenever the
    object carries Builder paint groups."""
    import os
    placed = None
    size = 0
    groups = json.loads(ob["paint_groups"])
    # multi-part objects get a 64px floor — 32px crams the layout unpaintably
    candidates = (32, 64, 128, 256, 512, 1024) if len(groups) <= 2 \
        else (64, 128, 256, 512, 1024)
    for candidate in candidates:
        try:
            placed = unwrap_grouped(ob, candidate, px_per_m)
            size = candidate
            break
        except RuntimeError:
            continue
    if placed is None:
        raise RuntimeError("object %s does not fit a 1024 texture" % ob.name)
    alb_path = os.path.join(tex_dir, "%s_tex.png" % ob.name)
    emi_path = os.path.join(tex_dir, "%s_emissive.png" % ob.name)
    img_a, img_e = paint_grouped(placed, size, alb_path, emi_path, px_per_m)
    if painted_dir:
        painted_a = os.path.join(painted_dir, "%s_tex.png" % ob.name)
        if os.path.exists(painted_a):
            img_a = bpy.data.images.load(painted_a)
            img_a.name = "%s_tex" % ob.name
        painted_e = os.path.join(painted_dir, "%s_emissive.png" % ob.name)
        if img_e is not None and os.path.exists(painted_e):
            img_e = bpy.data.images.load(painted_e)
            img_e.name = "%s_emissive" % ob.name
    strength = 1.0
    for p in placed:
        strength = max(strength, EMIT_STRENGTH.get(p["g"]["part"], 1.0))
    # A piece carrying any CARD is alpha-cutout: the card's transparent texels are
    # its form (a grate's holes, a leaf's silhouette), so the material must clip on
    # alpha or the holes render as solid dust-coloured squares.
    cutout = any(p["g"]["kind"] == "card" for p in placed)
    mat = make_atlas_material("%sTex" % ob.name, img_a, img_e, strength, cutout=cutout)
    # Record the atlas size on the object so the UV gate audits this piece at its
    # OWN texel density — auditing a 32px piece at a sweep's 512 hides real bleed.
    ob["atlas_px"] = size
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return size
