# Shared detail painters for paintlib pieces — the reusable material language
# (wood, crates, sheet metal, barrels, rusted struts) that any area build can
# register via pl.register_detail(name, fn). Area-specific painters (a drum's
# plate courses, a gate's rust bleed) stay in their area scripts.
#
# LAWS (each learned the hard way — see the wash-dressing review):
# - The unwrap is v-UP: tile row 0 is the WORLD BOTTOM of a side face. Gravity
#   cues (drips, welds, rust streaks) index from row ph-1 downward.
# - Accents must read on ANY base: lift() lerps toward a steel catch-light —
#   multiplying a near-black base stays near-black (the invisible-fin lesson).
# - face_rng() keys on the face's name/role/dims AND its group's atlas origin,
#   so same-sized faces vary instead of painting as clones, while every rebuild
#   reproduces identical pixels.
# - Painters receive the piece's REAL px_per_m — features authored in metres
#   (plank widths, sheet seams) must land at the piece's texel density.

import random
import zlib


def shade(c, f):
    return tuple(min(1.0, v * f) for v in c)


def lift(c, t, target=(0.62, 0.66, 0.72)):
    """Accent visibly on ANY base by lerping toward a steel catch-light."""
    return tuple(v + (tv - v) * t for v, tv in zip(c[:3], target))


def shadow(c, s):
    """Darken with strength s; near-black bases get a lifted scuff instead."""
    if sum(c[:3]) / 3.0 < 0.11:
        return lift(c, min(0.35, s * 0.5))
    return shade(c, 1.0 - s)


def face_rng(isl, salt=""):
    """Deterministic per-face rng: same face paints the same on every rebuild;
    the group's atlas origin keeps same-sized faces from painting as clones."""
    key = "%s:%s:%dx%d:%s:%s:%s" % (isl.get("name"), isl.get("role"),
                                    isl.get("pw", 0), isl.get("ph", 0),
                                    isl.get("ox", 0), isl.get("oy", 0), salt)
    return random.Random(zlib.crc32(key.encode()))


def role_fill(base, isl):
    role = isl.get("role")
    return shade(base, 1.1) if role == "top" else \
        shade(base, 0.8) if role == "bottom" else base


def paint_wood_grain(tile, mask, base, isl, px_per_m):
    """PLANKED wood: board divisions across the grain (a big face is boards,
    never one monolithic slab), per-board tone, grain streaks, rounded knots
    elongated along the grain."""
    ph, pw = tile.shape[:2]
    fill = role_fill(base, isl)
    tile[:, :] = fill
    rng = face_rng(isl, "grain")
    horiz = pw >= ph                                       # grain rides the long axis
    span, across = (pw, ph) if horiz else (ph, pw)

    def put(a_, s_, c):
        if horiz:
            tile[a_, s_] = c
        else:
            tile[s_, a_] = c

    bw = max(3, int(round(0.35 * px_per_m)))               # ~35cm boards
    nb = max(1, int(round(across / float(bw))))
    bh = across / float(nb)
    for b in range(nb):
        a0 = int(b * bh)
        a1 = across if b == nb - 1 else int((b + 1) * bh)
        board = shade(fill, rng.choice([0.9, 0.96, 1.0, 1.05]))
        if horiz:
            tile[a0:a1, :] = board
        else:
            tile[:, a0:a1] = board
        if b:                                              # gap shadow between boards
            put(a0, slice(0, span), shadow(fill, 0.45))
        for _ in range(1 + (span * max(1, a1 - a0)) // 70):
            aa = rng.randrange(a0 + 1, a1 - 1) if a1 - a0 > 2 else a0
            s0 = rng.randrange(0, max(1, span - 3))
            ln = rng.randrange(3, max(4, span // 3))
            put(aa, slice(s0, min(span, s0 + ln)), shade(board, rng.choice([0.82, 0.9, 1.08])))
        if a1 - a0 >= 5 and span >= 10 and rng.random() < 0.35:   # a rounded knot
            ka = rng.randrange(a0 + 2, a1 - 2)
            ks = rng.randrange(4, span - 4)
            for da in (-1, 0, 1):
                for ds in (-2, -1, 0, 1, 2):
                    if da * da * 3 + ds * ds <= 4:         # ellipse along the grain
                        put(ka + da, ks + ds,
                            shade(board, 0.45 if (da == 0 and ds == 0) else 0.62))
    if horiz and pw > 6:                                   # cut ends read darker
        tile[:, 0] = shade(fill, 0.7); tile[:, -1] = shade(fill, 0.7)
    elif not horiz and ph > 6:
        tile[0, :] = shade(fill, 0.7); tile[-1, :] = shade(fill, 0.7)


def paint_crate_face(tile, mask, base, isl, px_per_m):
    """Board slats with per-board tone, gap shadows, corner nails, chance brace."""
    ph, pw = tile.shape[:2]
    fill = role_fill(base, isl)
    tile[:, :] = fill
    rng = face_rng(isl, "crate")
    nslats = max(2, ph // max(4, ph // 3))
    slat_h = ph // nslats
    for s in range(nslats):
        y0, y1 = s * slat_h, ph if s == nslats - 1 else (s + 1) * slat_h
        board = shade(fill, rng.choice([0.9, 0.96, 1.0, 1.06]))
        tile[y0:y1, :] = board
        for _ in range(1 + pw // 6):                       # grain inside the board
            gy = rng.randrange(y0, max(y0 + 1, y1 - 1))
            gx = rng.randrange(0, max(1, pw // 2))
            tile[gy, gx:min(pw, gx + rng.randrange(3, max(4, pw // 3)))] = shade(board, 0.82)
        if s:                                              # gap shadow between boards
            tile[y0, :] = shadow(fill, 0.45)
    for ny in (1, ph - 2):                                 # corner nails
        for nx in (1, pw - 2):
            tile[ny, nx] = lift(fill, 0.5)
    if pw >= 12 and ph >= 12 and rng.random() < 0.5:       # diagonal brace
        for i in range(min(pw, ph) - 2):
            tile[1 + i, 1 + i] = shade(fill, 0.85)
            if 2 + i < ph:
                tile[2 + i, 1 + i] = shade(fill, 0.85)


def paint_metal_panel(tile, mask, base, isl, px_per_m):
    """Industrial sheet, readable on near-black parts: seam catch-lights + bright
    rivets (lerp-lifted, never multiplied), a weld line at the WORLD top, mineral
    drips running down from it."""
    ph, pw = tile.shape[:2]
    fill = role_fill(base, isl)
    tile[:, :] = fill
    rng = face_rng(isl, "panel")
    if ph < 5 or pw < 5:
        return
    step = max(5, int(round(0.8 * px_per_m)))              # ~80cm sheet widths
    for x in range(step, pw - 2, step):                    # seams + rivets
        tile[1:-1, x] = lift(fill, 0.14)
        for y in range(3, ph - 3, max(4, ph // 5)):
            tile[y, min(x + 1, pw - 1)] = lift(fill, 0.42)
    tile[ph - 2, 1:-1] = lift(fill, 0.2)                   # weld line at the top (v-up)
    for _ in range(max(1, pw // 9)):                       # mineral drips fall from it
        x = rng.randrange(1, pw - 1)
        ln = rng.randrange(3, max(4, ph // 2))
        tile[max(1, ph - 3 - ln):ph - 3, x] = lift(fill, 0.1)
    for _ in range((pw * ph) // 110):                      # scuffs
        y, x = rng.randrange(1, ph - 1), rng.randrange(1, pw - 1)
        tile[y, x] = lift(fill, rng.choice([0.08, 0.25]))


def paint_barrel(tile, mask, base, isl, px_per_m):
    """Iron drum: hoop bands on the shell, ringed lid with a bung on the caps."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    if isl.get("role") == "cap":
        r = min(pw, ph) // 2
        cy, cx = ph // 2, pw // 2
        for y in range(ph):
            for x in range(pw):
                d2 = (y - cy) ** 2 + (x - cx) ** 2
                if (r - 1.6) ** 2 <= d2 <= r * r:
                    tile[y, x] = shade(base, 0.6)          # rim ring
        tile[cy, cx] = shade(base, 0.5)                    # bung
        if cy + 1 < ph:
            tile[cy + 1, cx] = shade(base, 1.25)
        return
    for fy in (0.16, 0.5, 0.84):                           # hoops (per-segment rows align)
        y = min(ph - 1, max(0, int(ph * fy)))
        tile[y, :] = shadow(base, 0.4)
        if y + 1 < ph:
            tile[y + 1, :] = lift(base, 0.25)              # catch-light rides ABOVE (v-up)
    if pw > 2:
        tile[:, 0] = shadow(base, 0.15)                    # stave edge


def paint_truss(tile, mask, base, isl, px_per_m):
    """Rusted strut: end bolt plates + rust drips + worn edges."""
    ph, pw = tile.shape[:2]
    fill = role_fill(base, isl)
    tile[:, :] = fill
    rng = face_rng(isl, "truss")
    if ph < 6 or pw < 3:
        return
    long_v = ph >= pw
    for endf in (0.06, 0.94):                              # bolt pair near each end
        if long_v:
            y = min(ph - 2, max(1, int(ph * endf)))
            for x in (max(1, pw // 4), min(pw - 2, 3 * pw // 4)):
                tile[y, x] = lift(fill, 0.45)
        else:
            x = min(pw - 2, max(1, int(pw * endf)))
            for y in (max(1, ph // 4), min(ph - 2, 3 * ph // 4)):
                tile[y, x] = lift(fill, 0.45)
    for _ in range(max(2, (pw * ph) // 70)):               # rust wash streaking DOWN
        y, x = rng.randrange(1, ph - 1), rng.randrange(1, pw - 1)
        tile[y, x] = shade(fill, rng.choice([0.62, 0.75]))
        if y - 1 >= 1 and rng.random() < 0.6:
            tile[y - 1, x] = shade(fill, 0.7)
