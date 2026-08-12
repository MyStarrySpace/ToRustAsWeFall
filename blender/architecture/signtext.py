"""Sign text — the 3x5 font every painted sign in this world is set in.

It lives on its own because two builders need it, and because the orientation
below is the kind of thing that must have exactly one definition: a card's UVs
arrive with the V axis reversed against the array a painter writes into, so text
has to be laid down upside down to come out the right way up. Nothing else ever
noticed — a rootlet fan and a rust streak look the same either way — and a second
copy of this would be a second chance to get it wrong.
"""

# A 3x5 uppercase font. Three pixels wide is the narrowest a letter can be and
# still be told from its neighbours, and the placards are small enough that any
# wider would fit three words to a sign.
FONT = {
    "A": (0b010, 0b101, 0b111, 0b101, 0b101),
    "B": (0b110, 0b101, 0b110, 0b101, 0b110),
    "C": (0b011, 0b100, 0b100, 0b100, 0b011),
    "D": (0b110, 0b101, 0b101, 0b101, 0b110),
    "E": (0b111, 0b100, 0b110, 0b100, 0b111),
    "F": (0b111, 0b100, 0b110, 0b100, 0b100),
    "G": (0b011, 0b100, 0b101, 0b101, 0b011),
    "H": (0b101, 0b101, 0b111, 0b101, 0b101),
    "I": (0b111, 0b010, 0b010, 0b010, 0b111),
    "J": (0b001, 0b001, 0b001, 0b101, 0b010),
    "K": (0b101, 0b101, 0b110, 0b101, 0b101),
    "L": (0b100, 0b100, 0b100, 0b100, 0b111),
    "M": (0b101, 0b111, 0b111, 0b101, 0b101),
    "N": (0b101, 0b111, 0b111, 0b111, 0b101),
    "O": (0b010, 0b101, 0b101, 0b101, 0b010),
    "P": (0b110, 0b101, 0b110, 0b100, 0b100),
    "Q": (0b010, 0b101, 0b101, 0b110, 0b011),
    "R": (0b110, 0b101, 0b110, 0b101, 0b101),
    "S": (0b011, 0b100, 0b010, 0b001, 0b110),
    "T": (0b111, 0b010, 0b010, 0b010, 0b010),
    "U": (0b101, 0b101, 0b101, 0b101, 0b011),
    "V": (0b101, 0b101, 0b101, 0b101, 0b010),
    "W": (0b101, 0b101, 0b111, 0b111, 0b101),
    "X": (0b101, 0b101, 0b010, 0b101, 0b101),
    "Y": (0b101, 0b101, 0b010, 0b010, 0b010),
    "Z": (0b111, 0b001, 0b010, 0b100, 0b111),
    "0": (0b111, 0b101, 0b101, 0b101, 0b111),
    "1": (0b010, 0b110, 0b010, 0b010, 0b111),
    "2": (0b110, 0b001, 0b010, 0b100, 0b111),
    "3": (0b110, 0b001, 0b010, 0b001, 0b110),
    "4": (0b101, 0b101, 0b111, 0b001, 0b001),
    "5": (0b111, 0b100, 0b110, 0b001, 0b110),
    "6": (0b011, 0b100, 0b110, 0b101, 0b010),
    "7": (0b111, 0b001, 0b010, 0b010, 0b010),
    "8": (0b010, 0b101, 0b010, 0b101, 0b010),
    "9": (0b010, 0b101, 0b011, 0b001, 0b110),
    " ": (0b000, 0b000, 0b000, 0b000, 0b000),
    ".": (0b000, 0b000, 0b000, 0b000, 0b010),
    "-": (0b000, 0b000, 0b111, 0b000, 0b000),
    ":": (0b000, 0b010, 0b000, 0b010, 0b000),
    "/": (0b001, 0b001, 0b010, 0b100, 0b100),
    "*": (0b101, 0b010, 0b101, 0b000, 0b000),
    ">": (0b100, 0b010, 0b001, 0b010, 0b100),
}


def draw_text(tile, text, x0, y0, rgb, scale=1, emit=None):
    """Set `text` at (x0, y0) in 3x5 glyphs. Returns the x the line ended at.

    THE VERTICAL IS FLIPPED, THE HORIZONTAL IS NOT. A card's UVs arrive with the
    V axis reversed against the array these painters write into — nothing ever
    noticed, because a rootlet fan and a rust streak look the same upside down.
    Text does not.

    Getting this right took reading it off a RENDER rather than off the atlas: an
    atlas is stored bottom-up and mapped through UVs, so judging orientation from
    the atlas image says nothing about which way the letters face on the piece. A
    first guess of a full half-turn fixed the line order and left every word
    mirrored, which the atlas could not have told me either way.
    """
    ph, pw = tile.shape[:2]
    gw, gh = 4 * scale, 5 * scale
    block_w = len(text) * gw
    for i, ch in enumerate(text.upper()):
        glyph = FONT.get(ch, FONT[" "])
        for row in range(5):
            bits = glyph[row]
            for col in range(3):
                if not (bits >> (2 - col)) & 1:
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        lx = i * gw + col * scale + dx
                        ly = row * scale + dy
                        px = x0 + lx
                        py = y0 + (gh - 1 - ly)
                        if 0 <= px < pw and 0 <= py < ph:
                            tile[py, px, :3] = rgb
                            tile[py, px, 3] = 1.0
                            if emit is not None:
                                emit[py, px] = rgb
    return x0 + block_w


def text_width(text, scale=1):
    return len(text) * 4 * scale


