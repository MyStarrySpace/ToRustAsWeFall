# Tileable pixel-art FLOOD-WATER tiles for the channels (flooded Sector 12).
# Dark iron/teal flooded-water palette, 32 px (REPEAT-safe — all features wrap), to match the
# 32 px/m channels tile atlas (gen_tiles.py) and the camera_occlusion Bayer-dither grammar.
# The animated channels_water.gdshader scrolls + warps this tile; it just needs a believable
# still surface (caustic ripples, dark/light water cells, a few iron-bright flecks).
#
# Reproducible: run with PIL (pip install pillow). Writes v0 (+ a v1 variation) into the game
# resources dir. After running, import in Godot: ../godot.bat --headless --path "." --import
from PIL import Image
import os

T = 32  # 32 px / meter, matches the channels atlas

def q(c):
    return tuple(max(0, min(255, int(round(v)))) for v in c[:3]) + (255,)

def lerp(a, b, t):
    return q((a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t, a[2] + (b[2]-a[2])*t))

# 4x4 ordered (Bayer) dither — same deterministic pixel grammar as camera_occlusion.gdshader.
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# Flooded-water palette: deep dark-iron base, teal mid, brighter teal caustic crest, rare iron-sheen fleck.
DEEP = (8, 26, 34)      # darkest trough — dark iron-teal
BASE = (14, 44, 56)     # the bulk water
MID  = (22, 66, 80)     # mid teal swell
CREST = (46, 110, 120)  # caustic ripple crest (brighter teal)
SHEEN = (96, 150, 150)  # rare iron/teal sheen fleck
import math

def wrap_wave(x, y, seed):
    # Two summed sinusoids on integer wrap periods (so the tile repeats seamlessly): the wave
    # field a caustic ripple rides. Periods divide T (32) -> no seam.
    a = math.sin((x / T) * 2*math.pi * 2 + seed*1.7)        # period 16
    b = math.sin((y / T) * 2*math.pi * 3 + seed*0.9)        # period ~10.7 (3 cycles over 32)
    c = math.sin(((x + y) / T) * 2*math.pi * 1 + seed*2.3)  # period 32 diagonal swell
    return (a + b + 0.7*c) / 2.7  # -1..1-ish

def build(seed):
    img = Image.new("RGBA", (T, T), BASE)
    px = img.load()
    for y in range(T):
        for x in range(T):
            w = wrap_wave(x, y, seed)            # -1..1 swell field
            t = (w + 1.0) * 0.5                  # 0..1
            # Base gradient from DEEP (troughs) up through BASE to MID (swells), dithered so the
            # bands read as crisp pixel cells, not a smooth ramp.
            if t < 0.5:
                col = lerp(DEEP, BASE, t / 0.5)
            else:
                col = lerp(BASE, MID, (t - 0.5) / 0.5)
            px[x, y] = col
    # Caustic ripple CRESTS: where the wave field peaks, lay a Bayer-dithered bright-teal band so
    # the ripple lines read as pixel-art highlights (deterministic, wraps).
    for y in range(T):
        for x in range(T):
            w = wrap_wave(x, y, seed)
            crest_t = max(0.0, (w - 0.55) / 0.45)   # only the top of the swell crests
            if crest_t > 0.0 and (crest_t * 16) > BAYER[y % 4][x % 4]:
                px[x, y] = CREST
    # A few iron/teal sheen flecks at fixed wrap-safe positions (no RNG -> reproducible, seamless).
    flecks = [(5, 7), (19, 3), (27, 22), (11, 28), (3, 18), (23, 13)] if seed == 0 \
        else [(9, 4), (25, 9), (14, 21), (6, 26), (29, 16), (17, 30)]
    for (fx, fy) in flecks:
        px[fx % T, fy % T] = SHEEN
    return img

def main():
    root = "C:/Users/quest/Programming/Games/ToRustAsWeFall"
    out_dir = root + "/to-rust-as-we-fall/resources/models/channels"
    os.makedirs(out_dir, exist_ok=True)
    for v, seed in [(0, 0), (1, 1)]:
        img = build(seed)
        path = out_dir + "/channels_water_v%d.png" % v
        img.save(path)
        # 10x preview for eyeballing the tiling (gitignored tmp).
        img.resize((T*10, T*10), Image.NEAREST).save("C:/tmp/channels_water_v%d_preview.png" % v)
        # 2x2 tiled preview to confirm seamlessness.
        tiled = Image.new("RGBA", (T*2, T*2))
        for ty in range(2):
            for tx in range(2):
                tiled.paste(img, (tx*T, ty*T))
        tiled.resize((T*2*8, T*2*8), Image.NEAREST).save("C:/tmp/channels_water_v%d_tiled.png" % v)
        print("wrote %s (+ tmp previews)" % path)

if __name__ == "__main__":
    main()
