# Compose the LABELED archetype asset sheet from the per-piece cards Blender renders
# to C:\tmp\asset_cards\ (build_archetype_pieces.py). Grid of cards, each captioned
# with its piece name + content id, grouped: structures / flora / channels props.
from PIL import Image, ImageDraw, ImageFont
import pathlib, sys

sys.stdout.reconfigure(encoding="utf-8")
CARDS = pathlib.Path(r"C:\tmp\asset_cards")
OUT = pathlib.Path(r"C:\tmp\archetype_asset_sheet.png")

GROUPS = [
    ("STRUCTURES", [
        ("Barrier", "barrier"), ("CarryGear", "carry_gear"), ("ClassGate", "class_gate"),
        ("ForageCache", "forage_cache"), ("HideSlot", "hide_slot"), ("Junction", "junction"),
        ("Membrane", "membrane"), ("Pipe", "pipe"), ("Portal", "portal"),
        ("RootSlide", "root_slide"), ("Shelter", "shelter"), ("ShortcutGate", "shortcut_gate"),
        ("Terminal", "terminal"), ("WaterControl", "water_control"), ("Workbench", "workbench"),
    ]),
    ("FLORA (canon)", [
        ("Capbage", "capbage"), ("Scarpet", "scarpet"), ("Hushbloom", "hushbloom"),
        ("Flure", "flure"), ("Seefern", "seefern"), ("Climbvine", "climbvine"),
        ("Gasafoetida", "gasafoetida"), ("ForgetMeNots", "forget_me_nots"),
        ("ResolutionRoots", "resolution_roots"), ("MotherFlure", "mother_flure"),
    ]),
    ("CHANNELS PROPS (concept plates)", [
        ("VeinTrunk", "vein_trunk"), ("BiolumeCluster", "biolume_cluster"),
        ("Porthole", "porthole"),
        ("DeckPlanks", "deck_planks"), ("DeckGrate", "deck_grate"),
        ("WallTracery", "wall_tracery"), ("DoorIronband", "door_ironband"),
        ("RedBarLamp", "red_bar_lamp"), ("GateSign", "gate_sign"),
        ("PortalRingOrnate", "portal_ring_ornate"), ("PortalConsole", "portal_console"),
        ("PortalPadRings", "portal_pad_rings"), ("BallJointPipe", "ball_joint_pipe"),
        ("WaterChannel", "water_channel"), ("ReservoirPlatform", "reservoir_platform"),
        ("BrokenPier", "broken_pier"),
    ]),
    ("STRUCTURAL KIT (tileable)", [
        ("ScaffoldTruss", "scaffold_truss"), ("ScaffoldLeg", "scaffold_leg"),
        ("RailingRun", "railing_run"), ("PipeRack", "pipe_rack"),
        ("WallPanelTile", "wall_panel_tile"),
        ("DeckPlanksB", "deck_planks_b"), ("DeckPlanksC", "deck_planks_c"),
        ("DeckGrateB", "deck_grate_b"),
        ("WallPanelTileB", "wall_panel_tile_b"), ("WallPanelTileC", "wall_panel_tile_c"),
    ]),
]

CARD = 240          # displayed card size
CAP = 34            # caption bar height
PAD = 10
COLS = 6
HEAD = 44

try:
    font = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 15)
    font_head = ImageFont.truetype(r"C:\Windows\Fonts\consolab.ttf", 20)
except OSError:
    font = font_head = ImageFont.load_default()

rows_total = sum((len(items) + COLS - 1) // COLS for _, items in GROUPS)
W = COLS * (CARD + PAD) + PAD
H = PAD + sum(HEAD + ((len(items) + COLS - 1) // COLS) * (CARD + CAP + PAD)
              for _, items in GROUPS)
sheet = Image.new("RGB", (W, H), (14, 16, 19))
draw = ImageDraw.Draw(sheet)

y = PAD
missing = []
for title, items in GROUPS:
    draw.text((PAD + 2, y + 8), title, fill=(238, 194, 79), font=font_head)
    y += HEAD
    for i, (node, cid) in enumerate(items):
        cx = PAD + (i % COLS) * (CARD + PAD)
        cy = y + (i // COLS) * (CARD + CAP + PAD)
        p = CARDS / (node + ".png")
        if p.exists():
            card = Image.open(p).convert("RGB").resize((CARD, CARD), Image.LANCZOS)
            sheet.paste(card, (cx, cy))
        else:
            missing.append(node)
            draw.rectangle([cx, cy, cx + CARD, cy + CARD], outline=(200, 80, 80))
        draw.rectangle([cx, cy + CARD, cx + CARD, cy + CARD + CAP], fill=(24, 28, 33))
        draw.text((cx + 8, cy + CARD + 4), node, fill=(217, 226, 223), font=font)
        draw.text((cx + 8, cy + CARD + 19), cid, fill=(105, 214, 228), font=font)
    y += ((len(items) + COLS - 1) // COLS) * (CARD + CAP + PAD)

sheet.save(OUT)
print("sheet:", OUT, sheet.size, "missing:", missing or "none")
