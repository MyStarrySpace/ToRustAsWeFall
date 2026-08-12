# Per-face UV islands + the couch/bench paint grammar.
#
# The invariants (each one was a shipped bug before it was a rule):
# - UV corners map to texel CENTERS (half-texel inset) — mapping to island rect
#   edges samples the gutter and turns thin parts grey.
# - Tiny islands (<=4px a side) skip the edge border, or the border swallows the
#   base colour and the whole part reads near-black.
# - The atlas background is warm dust, never grey/black — residual bleed reads warm.
# - An object only gets an emissive texture when one of its parts declares "emit".

import bmesh
import random
import bpy
import math
import os
import numpy as np

from .palette import PARTS, ID_PARTS, EMIT_STRENGTH, DETAIL_PAINTERS, \
    DETAIL_NONE, DETAIL_SCREEN, DETAIL_RUG, DETAIL_ART, DETAIL_SPINES, \
    DETAIL_SHELF_BACK, DETAIL_PHOTO, DETAIL_MONO_WALL, DETAIL_DOOR

GUTTER = 2
DEFAULT_PX_PER_M = 32.0
TERMINAL_GREEN = (0.36, 0.91, 0.50)


def shade(rgb, k):
    return tuple(min(1.0, max(0.0, c * k)) for c in rgb)


def face_basis(f):
    n = f.normal
    e = None
    best = -1.0
    for loop in f.loops:
        d = loop.link_loop_next.vert.co - loop.vert.co
        if d.length > best:
            best = d.length
            e = d
    u = (e - n * e.dot(n)).normalized()
    v = n.cross(u)
    return u, v


def unwrap_and_pack(objs, atlas_px, px_per_m=DEFAULT_PX_PER_M):
    """Every face becomes its own island rect; shelf-pack all islands of all objs
    into one atlas. Returns islands: list of dicts with obj/face/px placement."""
    islands = []
    for ob in objs:
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        part_l = bm.faces.layers.int.get("part")
        det_l = bm.faces.layers.int.get("detail")
        uv_l = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            u, v = face_basis(f)
            pts = [(l.vert.co.dot(u), l.vert.co.dot(v)) for l in f.loops]
            minu, minv = min(p[0] for p in pts), min(p[1] for p in pts)
            pts = [(p[0] - minu, p[1] - minv) for p in pts]
            w = max(p[0] for p in pts)
            h = max(p[1] for p in pts)
            pw = max(3, int(round(w * px_per_m)))
            ph = max(3, int(round(h * px_per_m)))
            islands.append({
                "obj": ob, "bm": bm, "uv_l": uv_l, "face": f,
                "pts": pts, "w": w or 1e-6, "h": h or 1e-6, "pw": pw, "ph": ph,
                "part": ID_PARTS[f[part_l]] if part_l else "wood",
                "detail": f[det_l] if det_l else DETAIL_NONE,
            })
    # shelf pack, tallest first
    islands.sort(key=lambda i: -i["ph"])
    x = y = shelf_h = 0
    for isl in islands:
        pw, ph = isl["pw"] + GUTTER, isl["ph"] + GUTTER
        if x + pw > atlas_px - GUTTER:
            x = 0
            y += shelf_h
            shelf_h = 0
        if y + ph > atlas_px - GUTTER:
            raise RuntimeError("atlas overflow — grow atlas_px past %d" % atlas_px)
        isl["px"], isl["py"] = x + GUTTER, y + GUTTER
        x += pw
        shelf_h = max(shelf_h, ph)
    # write UVs with a half-texel inset so face corners sample island texel
    # centres, never the gutter (corner-on-boundary reads the background and
    # turns thin parts grey)
    for isl in islands:
        f, uv_l = isl["face"], isl["uv_l"]
        for loop, (pu, pv) in zip(f.loops, isl["pts"]):
            uu = (isl["px"] + 0.5 + pu / isl["w"] * (isl["pw"] - 1)) / atlas_px
            vv = (isl["py"] + 0.5 + pv / isl["h"] * (isl["ph"] - 1)) / atlas_px
            loop[uv_l].uv = (uu, vv)
    # flush bmeshes (one per object)
    done = set()
    for isl in islands:
        ob = isl["obj"]
        if ob.name not in done:
            isl["bm"].to_mesh(ob.data)
            done.add(ob.name)
    for isl in islands:
        isl.pop("bm", None)
        isl.pop("uv_l", None)
        isl.pop("face", None)
    return islands


def _poly_mask(pts, pw, ph, w, h):
    """Scanline-fill the island polygon into a (ph,pw) bool mask."""
    poly = [(p[0] / w * pw, p[1] / h * ph) for p in pts]
    mask = np.zeros((ph, pw), dtype=bool)
    n = len(poly)
    for row in range(ph):
        yc = row + 0.5
        xs = []
        for i in range(n):
            x1, y1 = poly[i]
            x2, y2 = poly[(i + 1) % n]
            if (y1 <= yc < y2) or (y2 <= yc < y1):
                xs.append(x1 + (yc - y1) / (y2 - y1) * (x2 - x1))
        xs.sort()
        for a, bx in zip(xs[0::2], xs[1::2]):
            i0, i1 = int(math.floor(a + 0.5)), int(math.ceil(bx - 0.5))
            if i1 >= i0:
                mask[row, max(0, i0):min(pw, i1 + 1)] = True
    if not mask.any():
        mask[:, :] = True
    return mask


# ------------------------------------------------- built-in detail painters ----
def _paint_rug(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    bw = max(2, int(0.18 * px_per_m))
    tile[:, :] = PARTS["rug_border"]["rgb"]
    tile[bw:-bw, bw:-bw] = base
    bw2 = bw + max(1, int(0.08 * px_per_m))
    tile[bw2:-bw2, bw2:-bw2] = shade(base, 0.94)


def _paint_art(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    sky1, sky2 = (0.72, 0.50, 0.44), (0.84, 0.66, 0.50)
    hill1, hill2 = (0.34, 0.45, 0.37), (0.22, 0.33, 0.30)
    tile[:, :] = sky1
    tile[: int(ph * 0.55), :] = sky2
    for cx_, w_, hgt, col in ((0.3, 0.5, 0.42, hill1), (0.72, 0.6, 0.30, hill2)):
        for xcol in range(pw):
            t = abs(xcol / pw - cx_) / (w_ / 2)
            if t < 1.0:
                hh = int(ph * hgt * (1.0 - t * t))
                tile[:hh, xcol] = col
    sy, sx_ = int(ph * 0.78), int(pw * 0.62)
    r = max(2, int(ph * 0.07))
    for yy in range(max(0, sy - r), min(ph, sy + r)):
        for xx in range(max(0, sx_ - r), min(pw, sx_ + r)):
            if (yy - sy) ** 2 + (xx - sx_) ** 2 <= r * r:
                tile[yy, xx] = (0.95, 0.88, 0.72)


def _paint_screen(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    for row in range(1, ph - 1, 3):
        tile[row, 1:-1] = shade(TERMINAL_GREEN, 0.35)
    if ph > 6:
        tile[ph - 4:ph - 2, 2:int(pw * 0.6)] = shade(TERMINAL_GREEN, 0.55)


def _paint_spines(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    for xcol in range(2, pw - 1, 3):
        tile[1:-1, xcol] = shade(base, 0.75)


def _paint_shelf_back(tile, mask, base, isl, px_per_m):
    tile[:, :] = shade(base, 0.88)


def _paint_door(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    midx = pw // 2
    tile[2:-2, midx] = shade(base, 0.7)                      # door seam
    for hx in (midx - max(2, pw // 8), midx + max(2, pw // 8)):
        if 0 < hx < pw:
            tile[ph // 2 - 1:ph // 2 + 1, hx] = shade(base, 0.6)  # handles


def _paint_photo(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    tile[: int(ph * 0.4), :] = (0.55, 0.62, 0.55)
    tile[int(ph * 0.4):int(ph * 0.62), :] = (0.72, 0.68, 0.58)


def _paint_panel_seams(tile, mask, base, isl, px_per_m):
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    for xcol in range(0, pw, max(4, int(1.2 * px_per_m / 2))):
        tile[:, xcol] = shade(base, 0.88)


DETAIL_PAINTERS.update({
    DETAIL_RUG: _paint_rug,
    DETAIL_ART: _paint_art,
    DETAIL_SCREEN: _paint_screen,
    DETAIL_SPINES: _paint_spines,
    DETAIL_SHELF_BACK: _paint_shelf_back,
    DETAIL_DOOR: _paint_door,
    DETAIL_PHOTO: _paint_photo,
    DETAIL_MONO_WALL: _paint_panel_seams,
})


def paint_atlas(islands, atlas_px, path_albedo, path_emissive,
                px_per_m=DEFAULT_PX_PER_M):
    alb = np.zeros((atlas_px, atlas_px, 4), dtype=np.float32)
    alb[:, :, :3] = (0.45, 0.38, 0.32)   # warm dust — any residual bleed reads warm
    alb[:, :, 3] = 1.0
    emi = np.zeros((atlas_px, atlas_px, 4), dtype=np.float32)
    emi[:, :, 3] = 1.0

    for isl in islands:
        part = PARTS[isl["part"]]
        base = part["rgb"]
        pw, ph, px, py = isl["pw"], isl["ph"], isl["px"], isl["py"]
        mask = _poly_mask(isl["pts"], pw, ph, isl["w"], isl["h"])
        tile = np.zeros((ph, pw, 3), dtype=np.float32)
        tile[:, :] = base

        det = isl["detail"]
        painter = DETAIL_PAINTERS.get(det)
        if painter is not None:
            painter(tile, mask, base, isl, px_per_m)

        # the edge grammar: a 1px darker border where the texture meets the
        # face edge (every island border is a mesh edge — the seam read), plus
        # EDGEWEAR: deterministic chips of worn-through metal on the exposed
        # borders (v-up: the upper rows of a side face, everywhere on a top
        # cap), and a doubled dark bottom border that grounds the shape. Tiny
        # islands (thin legs/cords) skip everything — at 3px wide the border
        # would swallow the base colour.
        if pw > 4 and ph > 4:
            edge = shade(part.get("edge", base), 0.68)
            border = mask & ~(
                np.roll(mask, 1, 0) & np.roll(mask, -1, 0) &
                np.roll(mask, 1, 1) & np.roll(mask, -1, 1))
            tile[border] = edge
            role = isl.get("role", "side")
            if role != "bottom":
                import zlib as _zl
                seed_key = "%s:%s:%d:%d" % (isl.get("name", ""), role, pw, ph)
                rr = random.Random(_zl.crc32(seed_key.encode()))
                steel = tuple(v + (t - v) * 0.55 for v, t in
                              zip(base[:3], (0.62, 0.66, 0.72)))
                rows, cols = np.nonzero(border)
                if rows.size:
                    if role == "top":
                        exposed = np.ones(rows.shape, dtype=bool)
                    else:
                        exposed = rows > int(ph * 0.55)
                    idx = np.nonzero(exposed)[0]
                    n_chips = max(1, idx.size // 9)
                    for _c in range(n_chips):
                        if idx.size == 0:
                            break
                        j = idx[rr.randrange(idx.size)]
                        tile[rows[j], cols[j]] = steel
                if role == "side" and ph >= 8:
                    low = border & (np.arange(ph)[:, None] <= 1)
                    tile[low] = shade(edge, 0.8)
        region = alb[py:py + ph, px:px + pw, :3]
        region[mask] = tile[mask]

        if "emit" in part:
            etile = np.zeros((ph, pw, 3), dtype=np.float32)
            etile[:, :] = part["emit"]
            if det == DETAIL_SCREEN:
                for row in range(1, ph - 1, 3):
                    etile[row, 1:-1] = shade(part["emit"], 0.4)
            eregion = emi[py:py + ph, px:px + pw, :3]
            eregion[mask] = etile[mask]

    def save(arr, path, name):
        img = bpy.data.images.new(name, atlas_px, atlas_px, alpha=True)
        img.pixels[:] = arr.ravel()
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return img

    has_emit = any("emit" in PARTS[isl["part"]] for isl in islands)
    img_a = save(alb, path_albedo, os.path.splitext(os.path.basename(path_albedo))[0])
    img_e = None
    if has_emit and path_emissive is not None:
        img_e = save(emi, path_emissive, os.path.splitext(os.path.basename(path_emissive))[0])
    return img_a, img_e


def make_atlas_material(name, img_albedo, img_emissive, emission_strength=1.0,
                        cutout=False):
    """cutout: wire the albedo's ALPHA to the BSDF and clip it. For CARD pieces —
    a grate drawn as pixel art on one plane, a leaf card — where the texture's
    transparent pixels ARE the silhouette. Clip, never blend: a blended card sorts
    badly against the outline mask and the perception overlays, and the art is
    hard-edged pixel art anyway, so there is nothing for a gradient to buy."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.9
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img_albedo
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if cutout:
        # MASK, never BLEND. Blender 4.2 removed the CLIP blend_method, so the only
        # portable way to make the glTF exporter emit alphaMode=MASK is to round the
        # alpha through a GREATER_THAN math node — the exporter recognises that
        # pattern and writes the cutoff. Left as plain BLEND, the card would sort
        # against the outline mask and the perception overlays the way every other
        # blended surface in this project has (see the overlay-materials law).
        cut = nt.nodes.new("ShaderNodeMath")
        cut.operation = 'GREATER_THAN'
        cut.inputs[1].default_value = 0.5
        nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
        nt.links.new(cut.outputs["Value"], bsdf.inputs["Alpha"])
        for attr, value in (("blend_method", 'BLEND'), ("alpha_threshold", 0.5)):
            if hasattr(mat, attr):
                try:
                    setattr(mat, attr, value)
                except (AttributeError, TypeError):
                    pass                       # enum varies across Blender versions
        mat.use_backface_culling = False       # a card is seen from both sides
    if img_emissive is not None:
        etex = nt.nodes.new("ShaderNodeTexImage")
        etex.image = img_emissive
        etex.interpolation = "Closest"
        if "Emission Color" in bsdf.inputs:
            nt.links.new(etex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def texture_object(ob, tex_dir, px_per_m=DEFAULT_PX_PER_M, painted_dir=None):
    """Give ONE object its own hand-paintable texture: per-face islands packed
    into the smallest square that fits, painted in the couch/bench grammar, an
    emissive sidecar only when the object has glowing parts.

    painted_dir: if <painted_dir>/<Name>_tex.png exists, the ARTIST'S painting is
    loaded for the material instead of the generated starter (which is still
    written next to it as a reference). Hand-paint survives regeneration as long
    as the object's geometry — and therefore its UV layout — is unchanged."""
    if "paint_groups" in ob:
        # Builder-made objects unwrap BlockBench-style: contiguous unfolded
        # boxes/strips, pixel-boundary UVs, edge-bleed — see boxatlas.py
        from .boxatlas import texture_object_grouped
        return texture_object_grouped(ob, tex_dir, px_per_m, painted_dir)
    islands = None
    size = 0
    for candidate in (32, 64, 128, 256, 512, 1024):
        try:
            islands = unwrap_and_pack([ob], candidate, px_per_m)
            size = candidate
            break
        except RuntimeError:
            continue
    if islands is None:
        raise RuntimeError("object %s does not fit a 1024 texture" % ob.name)
    alb_path = os.path.join(tex_dir, "%s_tex.png" % ob.name)
    emi_path = os.path.join(tex_dir, "%s_emissive.png" % ob.name)
    img_a, img_e = paint_atlas(islands, size, alb_path, emi_path, px_per_m)
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
    for isl in islands:
        strength = max(strength, EMIT_STRENGTH.get(isl["part"], 1.0))
    mat = make_atlas_material("%sTex" % ob.name, img_a, img_e, strength)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    # The UV gate audits a piece at its OWN texel density; record what it got.
    ob["atlas_px"] = size
    return size


def hue_replace(px, hue, keep_below_sat=0.14, sat_scale=1.0):
    """Vectorised hue replacement preserving S/V; low-saturation pixels stay
    neutral. For recoloured texture copies (the j-store pink/purple pattern)."""
    rgb = px[:, :, :3]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    delta = mx - mn
    sat = np.where(mx > 0, delta / np.maximum(mx, 1e-6), 0.0)
    sat = np.clip(sat * sat_scale, 0.0, 1.0)
    v = mx
    h6 = (hue * 6.0) % 6.0
    i = int(h6)
    f = h6 - i
    p = v * (1.0 - sat)
    q = v * (1.0 - sat * f)
    t = v * (1.0 - sat * (1.0 - f))
    lut = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    out = np.stack(lut, axis=2)
    mask = (sat > keep_below_sat)[:, :, None]
    px[:, :, :3] = np.where(mask, out, rgb)
    return px
