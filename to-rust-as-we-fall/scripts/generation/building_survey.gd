class_name BuildingSurvey
extends RefCounted

## THE MEASURED DRAWING of one district building, AS DATA — the single coordinate authority every
## construction pass reads (docs/SURVEY_REBUILD.md task 0; the director's measure-first method).
## A building is surveyed BEFORE it is meshed:
##   datums        named heights — plinth / storey tops / eave (top of the vertical wall band) / crown
##   plan          the axis-and-bay grid: drum (wall radius + bays) or box (half extents + wall faces)
##   profile       the silhouette r(y) (drum) or half-extents(y) (box) as ordered control points —
##                 this absorbs the old BaseShapeBuilder.massing_radius_at piecewise tables
##   reservations  a typed claim on wall space for EVERY planned part (openings, lattice fields,
##                 decorations, sockets) — two parts that want the same wall are reconciled HERE
##                 (restructure the field around the reservation, or fold the part into the base),
##                 so collisions are impossible by construction, never patched after meshing
##   sockets       the gameplay registry (doors, roads, bridges/lanes, weak points, balcony slots) —
##                 the architecture->puzzle contract, every socket ON a surveyed surface
##
## Consumers read the survey, not each other:
##   - door placement is door_placements() — LatticeBuilder.entrances emits meshes FROM it
##   - draped pipes follow radius_at() (the silhouette profile keeps parts on the real surface)
##   - gameplay anchors come from sockets (anchors() reshapes them for the existing consumers)
## The *_mesh builders in BaseShapeBuilder still carry their own construction constants; each
## building's task-1 rebuild (docs/SURVEY_REBUILD.md) moves its meshing onto the survey. Until then
## the profile tables here MIRROR those constants — keep them in lockstep, and validate() is the
## tripwire when they drift.

const EPS := 0.02                 # overlap / datum tolerance (m)
const DRUM_BAYS_FALLBACK := 8     # mirrors LatticeBuilder.TRACERY_DEFAULTS.bays (the drum plan grid)
const DEFAULT_STOREY := 2.7       # storey band height when a building has no authored storey plan

## Entrance parameters — placement half (main/side sizes, clearance) + mesh half (proud/recess/
## canopy). Placement is the survey's job; LatticeBuilder.entrances reads the same table for meshes.
const ENTRANCE_DEFAULTS := {
	"main_w": 1.6, "main_h": 2.7,
	"side_w": 1.1, "side_h": 2.1,
	"jamb": 0.20,        # frame post/lintel thickness
	"proud": 0.16,       # how far the frame stands off the wall
	"recess": 0.42,      # how deep the doorway pocket sinks in
	"canopy_out": 0.5,   # canopy overhang depth
	"side_count_min": 1, # range of SIDE entrances; the count is seeded per building
	"side_count_max": 3,
	"reserve_margin": 0.45,   # extra clearance (m) around a door the lattice must keep clear
}

## Eave datum (top of the vertical WALL band, where the crown/dome/roof takes over) as a fraction of
## total height, per composite. Each ratio traces to the massing constant that traces to the plate
## decomposition in docs/BUILDING_REVIEW.md.
const EAVE_RATIOS := {
	"plumbing_lobed": 0.65,    # dome springing, re-measured off the plate (drum band 0.47-0.65 H)
	"ancourage_domes": 0.47,   # wall top under the rolled brim (plate: brim band 0.47-0.59H)
	"hypelines_mound": 0.61,   # drum-band top / dome springing, re-measured off the plate
	"beacon_domed": 0.75,      # drum top / dome shoulder springing (plate: shoulder top ~75% H)
	"canopy_piers": 0.533,     # canopy slab underside at 3.2 m of 6.0 (plate: dais + open leg zone)
	"bulwark_towers": 0.86,    # gatehouse body top (towers rise past it to the crown)
	"zone3_split": 0.94,       # cornice underside (plate: crown slab = top ~6% H)
}

## THE PLUMBING POWER SURVEY — measured off the plate (reference-images/architecture/
## plumbing_power_project.png, decomposed 2026-07-10). Heights are FRACTIONS of the spec height H;
## angles are OFFSETS from the front axis (theta = PI/2, +Z), positive running leftward. Every part
## is reserved AND reconciled here: skirt fixtures snap to lobe CRESTS (slits/wheels) or VALLEYS
## (cascade, side pipe — the plate runs them in the grooves), nothing claims the door clearance
## below 1.95 m, slit bands stop where the flume's helical claim begins, and the side pipe's claim
## ends under the flume band it drinks from.
const PLUMBING := {
	# ONE lofted lathe profile: [y, ring radius, lobe amplitude]. The crest r*(1+amp) IS the
	# silhouette; the valley r*(1-amp) is the wall the door cuts (the lobe phase locks a valley
	# onto the front). Plate: fused root-skirt 0-0.47H (footprint 0.85H), shoulder drum 0.47-0.65H
	# (dia ~0.41H), onion dome 0.65-0.905H (overhang 1.15x drum), cupola 0.905-0.968H, crown cap.
	# 6 lobes (plate reads 6-8): at the 24-segment loft every crest AND valley lands exactly on a
	# vertex (4 samples per lobe), so the scallop reads bold instead of aliasing away.
	"lobes": 6,
	"rings": [
		[0.000, 0.355, 0.200], [0.100, 0.340, 0.190], [0.250, 0.290, 0.145],
		[0.400, 0.235, 0.055], [0.470, 0.205, 0.000], [0.650, 0.205, 0.000],
		[0.690, 0.235, 0.000], [0.760, 0.225, 0.000], [0.840, 0.175, 0.000],
		[0.880, 0.115, 0.000], [0.905, 0.048, 0.000], [0.968, 0.040, 0.000],
		[0.985, 0.030, 0.000], [0.998, 0.012, 0.000],
	],
	# The signature descending aqueduct as a survey HELIX: enters at the REAR riding the dome base,
	# crosses the front at 0.62H (the plate's glowing crossing), 1.25 turns, exits low right.
	# Section dims are fractions of H; the water strip is the terminal-green emissive.
	"flume": {
		"y_start": 0.76, "y_end": 0.41, "turns": 1.25, "theta_start_off": -PI,
		"trough_w": 0.075, "depth": 0.040, "rail_h": 0.052, "water_w": 0.055, "wall_sink": 0.012,
	},
	# Capillary slits [theta_off, y0, y1, w(frac)] — recessed dark, never emissive. Dome pair +
	# left single ride above the flume's high bands; the drum pair ends exactly where the front
	# crossing's claim begins; skirt slits sit on lobe crests clear of the wheel cluster.
	"slits": [
		[0.10, 0.70, 0.82, 0.018], [-0.10, 0.70, 0.82, 0.018], [0.48, 0.71, 0.79, 0.016],
		[0.08, 0.50, 0.595, 0.018], [-0.08, 0.50, 0.595, 0.018],   # over the sign, under the crossing
		[1.178, 0.27, 0.37, 0.020], [-1.963, 0.18, 0.30, 0.020], [2.749, 0.16, 0.26, 0.020],
		[-1.178, 0.28, 0.44, 0.020],
	],
	# The rusted handwheel cluster [theta_off, y_center, dia(frac)]: stacked pairs on the two lobe
	# crests left of the entry (the plate's lower-left cluster), linked by pipe runs at build time.
	"wheels": [
		[1.178, 0.115, 0.085], [1.178, 0.230, 0.062], [1.963, 0.175, 0.090], [1.963, 0.085, 0.062],
	],
	"stub_wheel": [2.30, 0.085, 0.070],   # freestanding, on a horizontal ground pipe stub
	"sign": {"theta_off": 0.0, "y0": 0.36, "y1": 0.48, "w": 1.0},   # board width in metres
	"hood": {"theta_off": 0.0, "ridge": 0.34, "eaves": 0.28, "w": 1.4, "out": 0.55},   # w/out metres
	"cascade": {"theta_off": 0.785, "y_top": 0.17, "w": 0.5},       # in a lobe valley; green glow
	"side_pipe": {"theta_off": -0.785, "y_top": 0.58, "dia": 0.033, "valve_y": 0.35},
	"ribs": {"count": 6, "theta0_off": 0.26, "y0": 0.72, "y1": 0.895, "r": 0.014},
}

## THE HYPELINES SURVEY — measured off the plate (reference-images/architecture/hypelines.png,
## decomposed 2026-07-10; several numbers correct the older review doc: body height ~1.24x the foot
## spread, mid arm pair at 0.61H, upper pair at 0.83H, the IRON HEART ghost letters sit BELOW the
## sign board, the entry arch reads ~0.35H). Heights are fractions of H, angles are offsets from the
## front axis. RECONCILED: the mid arm pair becomes the WALKABLE LANE pair with its deck snapped to
## the LEVEL-GRID datum (walk surface exactly level 1 x 4.0 m — the level layer docks it with zero
## tolerance fudging); the pitched upper/rear pairs stay scenery viaducts; the entry arch tops at
## 0.345H so the ghost-letter band clears it; ground pores sit outside the door clearance arc.
const HYPELINES := {
	# ONE lofted lathe: [y, ring radius, lobe amplitude] — root-lobe skirt 0-0.39H (foot 0.81H),
	# mid drum 0.39-0.61H (the sign band), top dome 0.61-1.0H, antenna mast above the cap.
	"lobes": 6,
	"rings": [
		[0.000, 0.325, 0.240], [0.100, 0.310, 0.220], [0.240, 0.262, 0.140],
		[0.390, 0.215, 0.000], [0.470, 0.225, 0.000], [0.560, 0.215, 0.000],
		[0.610, 0.205, 0.000], [0.720, 0.195, 0.000], [0.840, 0.165, 0.000],
		[0.920, 0.115, 0.000], [0.965, 0.060, 0.000], [0.990, 0.035, 0.000],
	],
	# The six pipe arms. az_off from the front, attach = pipe CENTER height (fraction of H),
	# pitch in radians, len in metres from the hub surface, pipe_r in metres.
	# The LANE pair is horizontal with its deck at walk_y = 4.0 m (level 1): pipe center
	# 4.0 - pipe_r - deck_t = 3.57 m = 0.576H (plate mid pair 0.61H, snapped to the datum).
	"arms": [
		{"az": 1.134, "attach": 0.576, "pitch": 0.0, "len": 4.2, "pipe_r": 0.31, "lane": true},
		{"az": -1.134, "attach": 0.576, "pitch": 0.0, "len": 4.2, "pipe_r": 0.31, "lane": true},
		{"az": 2.182, "attach": 0.830, "pitch": 0.38, "len": 4.5, "pipe_r": 0.31, "lane": false},
		{"az": -2.182, "attach": 0.830, "pitch": 0.38, "len": 4.5, "pipe_r": 0.31, "lane": false},
		{"az": 2.75, "attach": 0.700, "pitch": 0.18, "len": 4.6, "pipe_r": 0.28, "lane": false},
		{"az": -2.75, "attach": 0.700, "pitch": 0.18, "len": 4.6, "pipe_r": 0.28, "lane": false},
	],
	"deck": {"walk_y": 4.0, "deck_w": 0.9, "deck_t": 0.12, "rail_h": 0.32},   # metres (level 1 datum)
	"sign": {"y0": 0.43, "y1": 0.49, "w": 1.6},          # teal backlit board, front
	"ghost": {"y0": 0.372, "y1": 0.420, "w": 1.3},       # faded IRON HEART letters under it (y0 clears the 2.15 m door band at every rolled height)
	"toll": {"y0": 0.290, "y1": 0.325, "w": 0.9},        # FLOW OPTIMIZATION TOLL GATE, in the arch
	"arch": {"y_top": 0.345, "w": 1.5, "r_tube": 0.09},  # the parabolic entry arch rim
	"ramp": {"len": 2.4, "w": 1.2},                       # railed approach, metres
	"wheel": {"az": -0.84, "y": 0.78, "dia": 0.12},      # the signature valve wheel on the dome face
	"pores": [   # arched membrane pores [az_off, y0, y1, w(frac)]; glowing unless dark
		[0.87, 0.08, 0.20, 0.030], [1.31, 0.10, 0.19, 0.026], [-0.96, 0.12, 0.24, 0.030],
		[0.0, 0.53, 0.585, 0.026],
	],
	"vent": {"az": 0.0, "y0": 0.86, "y1": 0.93, "w": 0.022},   # dark recessed slit on the dome
	"mast": {"y_top": 1.09, "r": 0.006, "lights": 3},
}

## THE CLEANSTREETS SURVEY — measured off the plate (reference-images/architecture/
## cleanstreets_initiative.png, decomposed 2026-07-10). An OPEN toll-canopy pavilion: dais 0.115H,
## waisted-leg zone 0.42H (underside at 3.2 m), canopy slab + swept corner horns 0.45H. All values
## in METRES on the 11 x 6 x 7 spec box unless marked. RECONCILED: the pavilion has no front door —
## the main door rides the TOLL PORTAL on the +X flank (door_face/door_lateral), which is where the
## plate's road arrives; the queue front stays open lanes.
const CLEANSTREETS := {
	"dais": {"size": Vector3(10.4, 0.7, 6.6), "band_h": 0.42, "step_w": 1.3},
	# the pier grid: 2 rows x 3 columns of waisted mushroom legs, lofted foot->waist->head
	"piers": {"xs": [-3.7, 0.0, 3.7], "zs": [-2.2, 2.2],
		"foot_r": 0.62, "waist_r": 0.34, "head_r": 1.0, "waist_frac": 0.42},
	# the canopy: slab band 3.2-4.4 m, rim scallop, corner horns sweeping to the 6.0 m crown
	"canopy": {"y0": 3.2, "y1": 4.4, "scallop": 0.28, "horn_rise": 1.6, "horn_reach": 0.55},
	# queue divider fins (front-to-back walls between the pier columns), S-rise toward the rear
	"fins": {"xs": [-2.6, -0.87, 0.87, 2.6], "z0": -2.3, "z1": 2.3,
		"h_front": 1.1, "h_rear": 1.9, "t": 0.35},
	"spikes": {"z": 2.95, "count_per_lane": 5, "r": 0.05, "h": 0.16},
	"sign": {"y0": 3.5, "y1": 4.4, "w": 5.5},            # the fascia title board, front face
	"perf": {"x_center": 4.2, "y0": 3.4, "y1": 4.35, "half_w": 0.8, "holes": 7},   # corner clusters
	"toll": {"header_y0": 2.28, "header_y1": 2.78, "header_w": 1.6,   # clears the lintel top (2.2)
		"kiosk": Vector3(0.5, 1.9, 0.5), "cross": 0.4, "screen": 0.25},
	"vault": {"y": 3.14, "rib_r": 0.055, "light_r": 0.09},   # the warm-gold vaulted underside
	"monolith": {"z": 5.2, "x": -1.6, "w": 0.95, "h": 1.8, "base_h": 0.6},
}

## THE GREENFIELDS SURVEY — measured off the plate (reference-images/architecture/
## greenfields_collective.png, decomposed 2026-07-10). Four storeys (arcade 0.27H + 3 floors), each
## capped by a WAVY BONE SLAB (the stacked-cushions silhouette) carrying railings + greenery; round
## arcade arches with dark-green doors + warm sconces; 4 arched amber windows per facade per floor
## in bone niches; teal-lit roof terrace. ONE wave function (4 crests per facade, crests on the bay
## centres) shapes every slab. Values in METRES on the 5.2 x 6.4 x 5.0 box; storey datums come from
## STOREY_PLANS.greenfields (ground 1.7 + 3 x 1.5667 — the same datums the slab-ring reservations
## already ride). RECONCILED: window bands sit 0.62-1.44 above each storey base, clearing the sign
## board below and the next slab ring above.
const GREENFIELDS := {
	"slab": {"t": 0.18, "overhang": 0.35, "wave": 0.18, "crests": 4},
	"rail_h": 0.40,
	"arcade": {"bays": 4, "arch_w": 0.70, "spring": 0.90, "apex": 1.35, "sconce_y": 1.00},
	# window band as FRACTIONS of the storey band (floors vary per instance): [0.40, 0.80] keeps
	# the uniform beat clear of the sign below and the clamped top ring above at 3 AND 4 floors
	"window": {"per_face": 4, "band_y0": 0.40, "band_y1": 0.80, "w": 0.50, "frame": 0.07},
	"ribs": {"r": 0.055},
	"sign": {"y0": 1.72, "y1": 2.28, "w": 1.5},
	"roof": {"shrubs": 14, "buds": 12, "shrub_h": 0.85},
}

## THE ANCOURAGE SURVEY — measured off the plate (reference-images/architecture/ancourage.png,
## decomposed 2026-07-10). A squat pumphouse kiosk WIDER than tall (H ~0.93x W): body walls to
## 0.47H, the fat rolled BRIM (overhanging eave band) 0.47-0.59H, then the quilted 2-LOBE dome
## cluster to the crown — ONE continuous loft (the dome rings switch to 2-lobe modulation with
## rising amplitude; no intersecting spheres). Stacks + flame ride the saddle ABOVE the crown.
## The entry is the plate's grand arch: plank door below, glowing green cell-glass above; the
## root-fan of oily pipes spills from the plinth (details). Angles = offsets from the front.
const ANCOURAGE := {
	# [y, r, amp, lobes] — body round (6/0), brim flare, dome 2-lobed; crest = silhouette
	"rings": [
		[0.000, 0.489, 0.00, 6], [0.440, 0.489, 0.00, 6],
		[0.470, 0.553, 0.00, 6], [0.530, 0.565, 0.00, 6], [0.590, 0.520, 0.00, 6],
		[0.640, 0.470, 0.15, 2], [0.760, 0.430, 0.24, 2], [0.880, 0.330, 0.28, 2],
		[0.950, 0.200, 0.26, 2], [0.985, 0.090, 0.20, 2],
	],
	"dome_phase": 0.0,          # lobe crests at +-X: the entry front sits in the saddle valley
	"plinth": {"h": 0.36, "steps": 2, "out": 0.55},   # metres: stepped slab past the body
	# the entry idiom: outer arch + the green cell-glass band over the plank door (metres)
	"arch": {"w": 1.35, "door_h": 1.5, "apex": 2.16, "r_tube": 0.085,
		"glass_y0": 1.55, "glass_y1": 2.05, "mullions": 3},
	"readout": {"off": 0.62, "h": 1.05},              # the glowing box on a post, left of the door
	"sign": {"y0": 0.50, "y1": 0.575, "w": 1.55},     # cream Ancourage placard on the brim front
	"ppp": {"az": 2.42, "y0": 0.295, "y1": 0.40, "w": 0.80},   # district placard, left face
	# dome fixtures [az_off, y0, y1, w(frac)]: two multi-foil roses, the louver, two pores
	"roses": [[0.72, 0.70, 0.82, 0.100], [-0.72, 0.72, 0.83, 0.080]],
	"louver": {"az": -0.28, "y0": 0.72, "y1": 0.80, "w": 0.075},
	"pores": [[1.35, 0.68, 0.74, 0.045], [-1.30, 0.66, 0.72, 0.045]],
	# body fixtures: engaged pipes (az list), the big spoked wheel, the rosette port
	"engaged": {"azs": [1.85, 2.10, -1.95], "r": 0.045, "wheel_y": 0.30},
	"wheel": {"az": 2.75, "y": 0.33, "dia": 0.115},
	"rosette": {"az": -0.85, "y": 0.32, "dia": 0.095},
	# the saddle stacks (offsets along the lobe axis, metres; heights above the crown)
	"stacks": {"drum_x": -0.62, "drum_r": 0.34, "drum_h": 0.42,
		"flare_x": 0.55, "flare_r": 0.24, "flare_h": 0.95, "flame_h": 0.38},
	"roots": {"count": 11, "spread": 2.4, "reach": 3.2, "r": 0.085},   # fan ends ~1x building width out (plate)
	"seams": 2,                  # piped ridge tubes along the saddle valley
}

## THE BEACON HILL SURVEY — measured off the plate (reference-images/architecture/beacon_hill.png,
## decomposed 2026-07-11). A BELL-JAR urn (H:W ~1.30): slight base flare, near-vertical drum,
## dome shoulder curving into a raised LANTERN ringed by the planted roof garden. The middle half
## is FIVE colossal round-arch windows (center tallest, sills stepped) packed with amber shelf
## grids; the tracery RESTRUCTURES around those bay reservations (the standard lancet tracery
## populates only the unreserved rear via its existing reserved-arc mechanism). Ground band:
## portal + oval cartouche (the door's idiom), green status board left, the enforcement vestibule
## right (the ONE cyan accent). Angles are offsets from the front axis.
const BEACON := {
	# [y, r] fractions of H — the bell-jar profile, round (the ledge at 0.905 is the garden ring)
	"rings": [
		[0.000, 0.385], [0.080, 0.372], [0.150, 0.367], [0.600, 0.362], [0.760, 0.352],
		[0.830, 0.320], [0.880, 0.262], [0.905, 0.196], [0.908, 0.173], [0.975, 0.168],
	],
	# the five great arch bays [az_off, y0, y1]: center tallest, sills stepped clear of the door
	# clearance band (2.35 m) where their arcs cross it
	"bays": [
		[0.0, 0.40, 0.78], [0.44, 0.335, 0.76], [-0.44, 0.335, 0.76],
		[0.88, 0.30, 0.74], [-0.88, 0.30, 0.74],
	],
	"bay_half_arc": 0.17,        # radians of drum arc per bay
	"panes": {"cols": 3, "row_h": 0.34},   # the shelf grid: storey-scaled rows INSIDE bays only
	"cartouche": {"y0": 0.24, "y1": 0.315, "w": 1.55},   # the oval name board over the portal
	"status": {"az": 0.66, "y0": 0.05, "y1": 0.165, "w": 0.62},   # terminal-green board, left
	"vestibule": {"az": -0.74, "w": 1.05, "arch_apex": 2.05, "door_w": 0.85, "door_h": 1.6,
		"plaque_y0": 2.12, "plaque_y1": 2.42},           # the enforcement bay: the ONE cyan door
	"oculi": [[0.22, 0.815], [-0.22, 0.815], [0.66, 0.805], [-0.66, 0.805]],   # ovals between heads
	"lantern": {"clerestory": 6, "cy0": 0.925, "cy1": 0.965, "rail_h": 0.30, "tufts": 10},
	"beds": {"azs": [1.10, -1.10], "w": 0.9, "h": 0.45},   # planting beds at the front corners
	"ribs": {"pairs": true, "r": 0.045},                   # doubled bone ribs wrap the bays
}

## THE BULWARK WHARF SURVEY — measured off the plate (reference-images/architecture/
## bulwark_wharf.png, decomposed 2026-07-11). The barrier-maintenance GATEHOUSE: a squat box to the
## eave (0.86H) with FOUR corner towers grown from the box's own corners (splay foot / banded shaft
## / turret bulge / cap cone to the crown = H). The upper front is the FRAMED MEMBRANE — an
## ogee-crested frame holding a purple voronoi web, pierced by the ROSE APERTURE (0.28W, left of
## centre) and four pore portholes; rust WEEPS from the rose down over the sign band. Ground band:
## chamfered vault-door surround (wheel hub), green indicator left, pore-clamp readout + console
## kiosk right (all terminal green). Barrier WINGS run from both flanks on sagging posts.
## All values are FRACTIONS of the spec height H unless a key says metres.
const BULWARK := {
	# the corner tower loft [y, r] fractions of H: splay foot / shaft / turret bulge / cap cone
	"tower": {"r": 0.090, "rings": [
			[0.000, 0.122], [0.095, 0.100], [0.860, 0.090],
			[0.885, 0.108], [0.935, 0.108], [0.975, 0.055], [1.000, 0.012],
		], "collars": [0.25, 0.50, 0.75]},
	# the membrane frame: sagging bottom rail at y0, ogee crest rising to apex over the eave
	"frame": {"half_w": 0.346, "y0": 0.588, "y1": 0.856, "apex": 0.980, "rail_r": 0.016,
		"cupola": true},
	"rose": {"x": -0.0865, "y": 0.740, "r": 0.1115, "spokes": 8},
	# pore portholes [x, y, r] (4th entry 1 = the four-lobed wheel pore)
	"pores": [[-0.269, 0.658, 0.0327], [-0.269, 0.779, 0.0327],
		[0.246, 0.792, 0.0423, 1], [0.250, 0.673, 0.0365]],
	"weep": {"x": -0.0865, "half_w": 0.0346, "y0": 0.500, "y1": 0.623},
	"sign": {"half_w": 0.250, "y0": 0.465, "y1": 0.573},
	"readout": {"x": 0.319, "half_w": 0.0577, "y0": 0.375, "y1": 0.504},
	"indicator": {"x": -0.298, "half_w": 0.0288, "y0": 0.298, "y1": 0.356},
	"kiosk": {"x": 0.250, "half_w": 0.0481, "y1": 0.260},
	# the barrier wings: posts + sagging membrane bays off both flanks (lateral = rear-ward)
	"wing": {"lateral": -0.154, "attach_half_w": 0.0673, "bays": 3, "bay_len": 0.295,
		"panel_h": 0.721, "sag": 0.075, "post_r": 0.020},
	# the vault-door idiom (chamfered octagon surround + wheel hub); the generic stone is off
	"door": {"surround_half_w": 0.183, "surround_top": 0.442, "chamfer": 0.068, "hub_r": 0.058},
}

## THE ZONE-3 ERODED RUIN SURVEY — measured off the plate (reference-images/architecture/
## zone3_eroded_ruin.png, decomposed 2026-07-11). A two-storey verdigris SHOPFRONT ruin: the
## intact MAIN block (left ~2/3 of the plan) under the heavy eroded CORNICE slab; the right wing
## GUTTED — its facade torn off, three floor slabs exposed as open cavity galleries. Ground band:
## the slat-roofed PORCH row sheltering the boarded siding, the barred shop window and the entry
## (the porch IS the door idiom); the ALWAYS OPEN sign band between storeys; two arched window
## pairs + a wider center window above; the green terminal cabinet at the entry (sole emissive).
## Rust tendrils network the ground, climb the corners and drip from the cornice (layer-1 crust).
## All values are FRACTIONS of the spec height H unless a key says metres.
const ZONE3 := {
	"main_x0": -0.370, "main_x1": 0.111, "wing_x1": 0.370,   # the plan split datums
	"cornice_y": 0.94, "cornice_over": 0.065,
	"slabs": [0.30, 0.55, 0.78], "slab_t": 0.045,            # the torn wing's floor datums
	"porch": {"y0": 0.30, "y_wall": 0.46, "y_post": 0.38, "out": 0.145, "bays": 2,
		"left_wrap": true, "slats": 8},
	"siding": {"y1": 0.36, "rows": 6},
	"shop_window": {"x": -0.240, "half_w": 0.074, "y0": 0.10, "y1": 0.315, "bars": 3},
	"sign": {"x": -0.13, "half_w": 0.24, "y0": 0.43, "y1": 0.525},
	# upper windows [x_center, half_w, y0, y1] on the front; the side face carries two more
	"windows": [[-0.287, 0.0315, 0.60, 0.86], [-0.176, 0.0315, 0.60, 0.86],
		[0.009, 0.0465, 0.58, 0.88]],
	"side_windows": [[-0.093, 0.0315, 0.60, 0.86], [0.093, 0.0315, 0.60, 0.86]],
	"terminal": {"x": 0.20, "half_w": 0.030, "y1": 0.158},   # the cabinet, proud of the seam
	"tendrils": {"ground": 8, "reach": 0.60, "climbs": 3, "drips": 10},
	"cavity_half_w": 0.128,
}

## THE HONEYCOMB COOPERATIVE SURVEY — measured off the plate (reference-images/architecture/
## honeycomb_cooperative.png, decomposed 2026-07-11). A tall tenement slab whose intact faces wear
## the bone HONEYFRAME (the engine's sasb cell grid IS the facade bay grid — fixtures ride its
## real cell rects via honeyframe_cell_rects, never an invented grid): amber window panes (engine
## glass), a vent louver + planter per cell, the hex-badge sign filling a storey-2 cell. The +X
## flank is TORN: the frame is skipped there (skip_faces) and the face wears rust wash, a
## two-storey HOLE full of strut chaos, and three CATWALK rows with ember lights (plate-demanded
## warm). A ring-balustrade parapet rides the crown; the entry idiom is the teal door + cyan
## transom + warm sconces + CRT kiosk + planter boxes. Fractions of H unless a key says metres.
const HONEYCOMB := {
	"catwalks": {"rows": [0.22, 0.475, 0.73], "out": 0.045, "rail_h": 0.034, "posts": 4},
	"hole": {"z": -0.05, "half_w": 0.16, "y0": 0.30, "y1": 0.62, "struts": 9},
	"embers": 7,
	"parapet": {"spacing": 0.42, "baluster_r": 0.055, "post_r": 0.045, "tip_h": 0.30},
	"sign_cell": {"x": 0.0, "half_w": 0.075, "y0": 0.32, "y1": 0.415},
	"fixtures": {"vent_w": 0.30, "vent_h": 0.22, "planter_h": 0.11},
	"entry": {"transom_h": 0.20, "sconce_off": 1.00, "sconce_y": 1.90,
		"kiosk_x": 0.95, "planters_x": [-1.35, -1.85]},
	"rust": {"streaks": 8},
}

## THE OPEN FILES INITIATIVE SURVEY — measured off the plate (reference-images/architecture/
## open_files_initiative.png, decomposed 2026-07-11). The MASSING stays the director's recursive
## connected awnings (geometry-lab algo 2 — untouched); the rack STRATA live on the awning-level
## datums the rackwork already reads (_awning_layout is the shared authority). This table owns the
## GROUND IDIOM: the nested hex-arch PORTAL pouring cyan light + the scan-beam fan on the
## threshold, the heraldic crest + the glowing green sign over it, flanking console pedestals,
## fin sconces and the apron bollards. Values are METRES at the canonical H 9.0 (the massing
## rolls +-6%; the door region is reconciled against the sign at every roll).
const OPEN_FILES := {
	"portal": {"frames": 3, "frame_step": 0.16, "chamfer": 0.42},
	"scan": {"len": 2.6, "half_ang": 0.42, "bar_y": 1.1},
	"sign": {"y0": 3.05, "y1": 3.70, "w": 3.0},
	"crest": {"y0": 3.85, "y1": 4.35, "w": 0.66},
	"consoles": {"xs": [-1.95, 1.95]},
	"sconces": {"xs": [-2.45, 2.45], "ys": [2.3, 4.6]},
	"bollards": {"count": 7, "radius": 3.6},
}

## Authored storey plans (ground band + floor count between plinth and eave), per building kind.
## Numbers trace to the plate decompositions; buildings without an entry get equal DEFAULT_STOREY
## bands. greenfields' ground/storey split is ALSO the slab-ring datum table the massing builds on.
const STOREY_PLANS := {
	"honeycomb_cooperative": {"ground_factor": 1.2, "floors": 6},   # plate: tall ground + 6 floors
	"greenfields": {"ground": 1.7, "floors": 3},                    # plate: arcade + 3 floors
}

var kind := ""
var spec: Dictionary = {}
var datums: Dictionary = {"plinth": 0.0, "storeys": [], "eave": 0.0, "crown": 0.0}
var plan: Dictionary = {}
var profile: Array = []          # drum: [{y, r}] / box: [{y, hx, hz}] — ascending y, steps allowed
var reservations: Array = []     # typed wall claims (openings carry the legacy door-region keys)
var sockets: Array = []          # {kind: door|road|bridge|weak_point|balcony, pos, ...}


# ============================================================================================
# PARAMETRIC VARIATION — the const tables are CANONICAL PLATE SPECIMENS of each district TYPE.
# BaseShapeBuilder.generate(kind, seed) rolls plate-plausible variation (roll_vars) into
# spec["vars"]; every table read goes through table_for(), which overlays it. Dependent values
# (door valley radius, sign bands at four floors) are RE-RECONCILED inside the roller, and the
# seed-sweep test proves every variant still surveys clean.
# ============================================================================================

## The named canonical table, overlaid with this instance's rolled variation (arrays REPLACE,
## dictionaries merge one level deep — the tables are flat dicts of scalars/arrays/sub-dicts).
static func table_for(spec_in: Dictionary, name: String) -> Dictionary:
	var base: Dictionary = {}
	match name:
		"plumbing":
			base = PLUMBING
		"hypelines":
			base = HYPELINES
		"cleanstreets":
			base = CLEANSTREETS
		"greenfields":
			base = GREENFIELDS
		"ancourage":
			base = ANCOURAGE
		"beacon":
			base = BEACON
		"bulwark":
			base = BULWARK
		"zone3":
			base = ZONE3
		"honeycomb":
			base = HONEYCOMB
		"open_files":
			base = OPEN_FILES
	var out := base.duplicate(true)
	var over: Dictionary = (spec_in.get("vars", {}) as Dictionary).get(name, {})
	for k in over.keys():
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			var sub := (out[k] as Dictionary)
			for k2 in (over[k] as Dictionary).keys():
				sub[k2] = (over[k] as Dictionary)[k2]
		else:
			out[k] = over[k]
	return out

## Roll one variant of a building TYPE. seed 0 = the canonical plate specimen (empty roll).
## Returns {"spec": {spec-key overrides}, "<table>": {table overlays}}. Every dependent value is
## reconciled HERE (the roller is part of the survey), so a variant can never ship a collision the
## canonical reconciliation only fixed for the canonical numbers.
static func roll_vars(kind_in: String, seed_value: int) -> Dictionary:
	if seed_value == 0:
		return {}
	var rng := SeededRng.new((seed_value * 2654435761) ^ (str(kind_in).hash() & 0x7fffffff))
	var out := {"spec": {}}
	match kind_in:
		"plumbing_power":
			var h := 5.6 * lerpf(0.97, 1.06, float(rng.call("randf")))
			# the door dims scale WITH the drum so the clearance arc never swallows the cascade
			# valley at 0.785 rad (the fixed 6-lobe geometry)
			(out["spec"] as Dictionary)["height"] = h
			(out["spec"] as Dictionary)["radius"] = 0.355 * 1.20 * h
			(out["spec"] as Dictionary)["door_radius"] = 0.355 * 0.80 * h
			(out["spec"] as Dictionary)["entrances"] = {"main_w": 0.9 * h / 5.6, "main_h": 1.5,
				"side_count_min": 0, "side_count_max": 0, "reserve_margin": 0.25,
				"canopy_out": 0.0, "main_surround": false}
			var fl := {"turns": [1.0, 1.25][int(rng.call("randi_range", 0, 1))],
				"y_start": lerpf(0.73, 0.79, float(rng.call("randf")))}
			var pl := {"flume": fl, "sign": {"w": lerpf(0.9, 1.1, float(rng.call("randf")))},
				"ribs": {"theta0_off": lerpf(0.22, 0.36, float(rng.call("randf")))}}   # clear of the dome slits at +-0.10/+0.48
			if float(rng.call("randf")) < 0.4:
				var wh: Array = (PLUMBING["wheels"] as Array).duplicate(true)
				wh.remove_at(1)   # the upper stacked wheel is optional on this lobe
				pl["wheels"] = wh
			var drop: Array = []
			for cand in [6, 7]:
				if float(rng.call("randf")) < 0.35:
					drop.append(cand)
			if not drop.is_empty():
				var sl: Array = []
				var src: Array = PLUMBING["slits"]
				for i in range(src.size()):
					if not drop.has(i):
						sl.append((src[i] as Array).duplicate())
				pl["slits"] = sl
			out["plumbing"] = pl
		"hypelines":
			var h2 := 6.2 * lerpf(0.95, 1.055, float(rng.call("randf")))
			(out["spec"] as Dictionary)["height"] = h2
			(out["spec"] as Dictionary)["radius"] = 0.325 * 1.24 * h2
			(out["spec"] as Dictionary)["door_radius"] = 0.325 * 0.76 * h2
			var arms: Array = (HYPELINES["arms"] as Array).duplicate(true)
			var upitch := lerpf(0.32, 0.44, float(rng.call("randf")))
			for a in arms:
				var ad := a as Dictionary
				if not bool(ad["lane"]) and absf(float(ad["az"])) < 2.5:
					ad["pitch"] = upitch
					ad["len"] = float(ad["len"]) * lerpf(0.9, 1.08, float(rng.call("randf")))
				elif bool(ad["lane"]):
					ad["len"] = lerpf(3.9, 4.5, float(rng.call("randf")))
			if float(rng.call("randf")) < 0.4:
				arms = arms.filter(func(a2): return absf(float((a2 as Dictionary)["az"])) < 2.5)
			var hy := {"arms": arms,
				"wheel": {"dia": lerpf(0.10, 0.13, float(rng.call("randf")))},
				"mast": {"y_top": lerpf(1.06, 1.12, float(rng.call("randf")))}}
			if float(rng.call("randf")) < 0.3:
				hy["ghost"] = {"w": 0.0}   # the ghost letters weathered away on this instance
			out["hypelines"] = hy
		"greenfields":
			var floors := 3 if float(rng.call("randf")) < 0.55 else 4
			(out["spec"] as Dictionary)["storey_floors"] = floors
			var bays := int(rng.call("randi_range", 3, 5))
			var g := {"slab": {"wave": lerpf(0.12, 0.24, float(rng.call("randf"))),
					"overhang": lerpf(0.28, 0.42, float(rng.call("randf")))},
				"window": {"per_face": bays},
				"arcade": {"bays": bays},
				"roof": {"buds": int(rng.call("randi_range", 8, 16)),
					"shrubs": int(rng.call("randi_range", 10, 18))},
				"sign": {"w": lerpf(1.3, 1.7, float(rng.call("randf")))}}
			if floors == 4:
				# four thinner storeys: the sign band drops so the lower window band clears it
				g["sign"] = {"y0": 1.70, "y1": 2.14, "w": float((g["sign"] as Dictionary)["w"])}
			out["greenfields"] = g
		"ancourage":
			var h3 := 4.6 * lerpf(0.95, 1.05, float(rng.call("randf")))
			(out["spec"] as Dictionary)["height"] = h3
			(out["spec"] as Dictionary)["radius"] = 0.565 * h3
			(out["spec"] as Dictionary)["door_radius"] = 0.489 * h3
			var amp_s := lerpf(0.85, 1.15, float(rng.call("randf")))
			var rows: Array = []
			for row_v in (ANCOURAGE["rings"] as Array):
				var rw := (row_v as Array).duplicate()
				rw[2] = float(rw[2]) * amp_s
				rows.append(rw)
			# the arch is metre-scaled (character door) but the sign band is an h-fraction: at low
			# rolled heights they'd collide — the arch scales with the roll (sweep-caught)
			var ak := h3 / 4.6
			var an := {"rings": rows,
				"arch": {"apex": 2.16 * ak, "glass_y0": 1.55, "glass_y1": 1.55 + 0.50 * ak},
				"dome_phase": lerpf(-0.25, 0.25, float(rng.call("randf"))),
				"sign": {"w": lerpf(1.4, 1.7, float(rng.call("randf")))},
				"roots": {"count": int(rng.call("randi_range", 8, 14)),
					"reach": lerpf(2.8, 3.6, float(rng.call("randf")))},
				"stacks": {"flare_h": 0.95 * lerpf(0.85, 1.15, float(rng.call("randf"))),
					"drum_h": 0.42 * lerpf(0.85, 1.15, float(rng.call("randf")))}}
			if float(rng.call("randf")) < 0.25:
				an["louver"] = {"w": 0.0}   # some instances weld the vent shut
			out["ancourage"] = an
		"beacon_hill":
			var hb := 7.2 * lerpf(0.96, 1.05, float(rng.call("randf")))
			(out["spec"] as Dictionary)["height"] = hb
			(out["spec"] as Dictionary)["radius"] = 0.385 * hb
			(out["spec"] as Dictionary)["door_radius"] = 0.361 * hb   # the taper's narrowest in the door band
			(out["spec"] as Dictionary)["tracery_height"] = 0.75 * hb
			var bc := {"panes": {"cols": int(rng.call("randi_range", 3, 4))},
				"lantern": {"clerestory": int(rng.call("randi_range", 5, 8)),
					"tufts": int(rng.call("randi_range", 8, 14))},
				"cartouche": {"w": lerpf(1.4, 1.7, float(rng.call("randf")))}}
			if float(rng.call("randf")) < 0.3:
				bc["oculi"] = [[0.22, 0.815], [-0.22, 0.815]]   # a plainer dome on some instances
			out["beacon"] = bc
		"bulwark_wharf":
			var s7 := lerpf(0.95, 1.06, float(rng.call("randf")))
			(out["spec"] as Dictionary)["size"] = Vector3(4.6, 5.2, 3.4) * s7
			# the door scales with the box so the vault surround keeps wrapping it
			(out["spec"] as Dictionary)["entrances"] = {"main_w": 1.15 * s7, "main_h": 2.0 * s7,
				"side_count_min": 0, "side_count_max": 0, "canopy_out": 0.0,
				"reserve_margin": 0.18, "main_surround": false}
			# RECONCILED IN THE ROLLER: rose x >= -0.10 keeps its rim clear of the left pores;
			# r <= 0.112 keeps its crown under the frame band top (0.856)
			var bw := {"rose": {"x": lerpf(-0.10, -0.04, float(rng.call("randf"))),
					"r": lerpf(0.100, 0.112, float(rng.call("randf")))},
				"wing": {"bays": int(rng.call("randi_range", 2, 3))},
				"sign": {"half_w": lerpf(0.225, 0.252, float(rng.call("randf")))},   # <= readout x0 0.261
				"frame": {"cupola": float(rng.call("randf")) < 0.7}}
			if float(rng.call("randf")) < 0.3:
				bw["pores"] = [[-0.269, 0.658, 0.0327], [0.246, 0.792, 0.0423, 1],
					[0.250, 0.673, 0.0365]]   # a plainer membrane on some instances
			out["bulwark"] = bw
		"zone3":
			var s8 := lerpf(0.94, 1.06, float(rng.call("randf")))
			(out["spec"] as Dictionary)["size"] = Vector3(4.0, 5.4, 3.6) * s8
			(out["spec"] as Dictionary)["entrances"] = {"main_w": 1.0 * s8, "main_h": 1.9 * s8,
				"side_count_min": 0, "side_count_max": 0, "canopy_out": 0.0,
				"reserve_margin": 0.18, "main_surround": false}
			var z3v := {"sign": {"half_w": lerpf(0.215, 0.237, float(rng.call("randf")))},   # edge < cavity x0 0.2405-0.128
				"porch": {"bays": int(rng.call("randi_range", 2, 3)),
					"left_wrap": float(rng.call("randf")) < 0.6},
				"tendrils": {"ground": int(rng.call("randi_range", 6, 12)),
					"climbs": int(rng.call("randi_range", 2, 3)),
					"drips": int(rng.call("randi_range", 7, 14))}}
			if float(rng.call("randf")) < 0.35:
				z3v["slabs"] = [0.36, 0.66]   # a two-gallery ruin on some instances
			out["zone3"] = z3v
		"honeycomb_cooperative":
			var s9 := lerpf(0.94, 1.06, float(rng.call("randf")))
			(out["spec"] as Dictionary)["size"] = Vector3(4.5, 10.0, 6.3) * s9
			(out["spec"] as Dictionary)["entrances"] = {"main_w": 1.6 * s9, "main_h": 2.7 * s9,
				"side_count_min": 0, "side_count_max": 0, "canopy_out": 0.0,
				"reserve_margin": 0.2, "main_surround": false}
			var hcv := {"embers": int(rng.call("randi_range", 5, 9)),
				"hole": {"half_w": lerpf(0.13, 0.18, float(rng.call("randf"))),
					"y1": lerpf(0.58, 0.66, float(rng.call("randf")))},
				"rust": {"streaks": int(rng.call("randi_range", 6, 11))}}
			if float(rng.call("randf")) < 0.35:
				hcv["catwalks"] = {"rows": [0.30, 0.62]}   # a two-catwalk flank on some instances
			out["honeycomb"] = hcv
		"open_files":
			var k10 := lerpf(0.94, 1.06, float(rng.call("randf")))
			(out["spec"] as Dictionary)["size"] = Vector3(5.6, 9.0, 5.6) * k10
			(out["spec"] as Dictionary)["entrances"] = {"main_w": 1.5 * k10, "main_h": 2.2 * k10,
				"side_count_min": 0, "side_count_max": 0, "canopy_out": 0.0,
				"reserve_margin": 0.25, "main_surround": false}
			(out["spec"] as Dictionary)["awning_depth"] = int(rng.call("randi_range", 2, 3))
			(out["spec"] as Dictionary)["awning_merge"] = lerpf(0.40, 0.70, float(rng.call("randf")))
			var ofv := {"portal": {"frames": int(rng.call("randi_range", 2, 3))},
				"bollards": {"count": int(rng.call("randi_range", 5, 9))},
				"sign": {"w": lerpf(2.7, 3.2, float(rng.call("randf")))}}
			out["open_files"] = ofv
		"cleanstreets":
			var spread := lerpf(2.2, 2.8, float(rng.call("randf")))
			var cs := {"fins": {"xs": [-spread, -spread / 3.0, spread / 3.0, spread],
					"h_rear": lerpf(1.7, 2.1, float(rng.call("randf")))},
				"spikes": {"count_per_lane": int(rng.call("randi_range", 4, 6))},
				"canopy": {"scallop": lerpf(0.20, 0.34, float(rng.call("randf")))},
				"perf": {"holes": int(rng.call("randi_range", 5, 9))},
				"monolith": {"z": 5.2, "x": lerpf(-2.2, -1.0, float(rng.call("randf")))},
				"toll": {"header_w": lerpf(1.4, 1.8, float(rng.call("randf")))}}
			out["cleanstreets"] = cs
		_:
			# the not-yet-rebuilt types take a plain size/height jitter (their massing constants
			# are ratios, so they scale coherently); beacon's absolute tracery height scales too.
			# tiered_terrace floors down-scale less: its bottom tier band must keep the 2.7 m door.
			var k_lo := 0.985 if kind_in == "tiered_terrace" else 0.94
			var k := lerpf(k_lo, 1.06, float(rng.call("randf")))
			var spec0: Dictionary = BaseShapeBuilder.SPECS.get(kind_in, {})
			if spec0.has("size"):
				(out["spec"] as Dictionary)["size"] = (spec0["size"] as Vector3) * k
			if spec0.has("height"):
				(out["spec"] as Dictionary)["height"] = float(spec0["height"]) * k
			if spec0.has("radius"):
				(out["spec"] as Dictionary)["radius"] = float(spec0["radius"]) * k
			if spec0.has("door_radius"):
				(out["spec"] as Dictionary)["door_radius"] = float(spec0["door_radius"]) * k
			if spec0.has("tracery_height"):
				(out["spec"] as Dictionary)["tracery_height"] = float(spec0["tracery_height"]) * k
	return out


## Survey a building from its BaseShapeBuilder spec (generate() output; raw SPECS entries work too).
## `plate_ratios` lets a per-building rebuild override datum ratios measured off the plate.
static func from_spec(spec_in: Dictionary, plate_ratios: Dictionary = {}) -> BuildingSurvey:
	var sv := BuildingSurvey.new()
	sv.spec = spec_in.duplicate(true)
	sv.kind = str(spec_in.get("kind", ""))
	sv._survey_datums(plate_ratios)
	sv._survey_plan()
	sv._survey_profile()
	var placements := door_placements(sv.spec)
	sv._survey_reservations(placements)
	sv._survey_sockets(placements)
	return sv

func _height_total() -> float:
	if spec.has("height_total"):
		return float(spec["height_total"])
	if spec.has("size"):
		return (spec["size"] as Vector3).y
	return float(spec.get("height", 6.0))

func _footprint() -> float:
	if spec.has("footprint"):
		return float(spec["footprint"])
	if spec.has("size"):
		var s: Vector3 = spec["size"]
		return maxf(s.x, s.z)
	return float(spec.get("radius", 2.5)) * 2.0 * float(spec.get("flare", 1.0))

func _is_drum() -> bool:
	return str(spec.get("shape", "")) == "cylinder" or (spec.has("radius") and not spec.has("size"))


# ============================================================================================
# SURVEY PASSES — datums, plan, profile, reservations, sockets
# ============================================================================================

func _survey_datums(plate_ratios: Dictionary) -> void:
	var h := _height_total()
	var comp := str(spec.get("composite", ""))
	var eave_ratio := float(plate_ratios.get("eave", EAVE_RATIOS.get(comp, 1.0)))
	datums["plinth"] = 0.0
	datums["eave"] = h * eave_ratio
	datums["crown"] = h
	var eave := float(datums["eave"])
	var storeys: Array = []
	var sp: Dictionary = STOREY_PLANS.get(kind, {})
	if plate_ratios.has("storeys"):
		storeys = (plate_ratios["storeys"] as Array).duplicate()
	elif sp.has("ground"):
		var ground := float(sp["ground"])
		var floors := int(spec.get("storey_floors", sp["floors"]))
		var band := (eave - ground) / float(maxi(1, floors))
		storeys.append(ground)
		for k in range(1, floors + 1):
			storeys.append(ground + band * float(k))
	elif sp.has("ground_factor"):
		var gf := float(sp["ground_factor"])
		var floors := int(sp["floors"])
		var f := eave / (gf + float(floors))
		storeys.append(gf * f)
		for k in range(1, floors + 1):
			storeys.append(gf * f + f * float(k))
	else:
		var n := maxi(1, int(round(eave / DEFAULT_STOREY)))
		for k in range(1, n + 1):
			storeys.append(eave * float(k) / float(n))
	datums["storeys"] = storeys

func _survey_plan() -> void:
	if _is_drum():
		plan = {
			"kind": "drum",
			"radius": float(spec.get("radius", 2.0)),
			# the wall the doors actually cut (the plumbing drum sits inside its lobed skirt)
			"wall_radius": float(spec.get("door_radius", spec.get("radius", 2.0))),
			"bays": int(spec.get("bays", DRUM_BAYS_FALLBACK)),
			"front_theta": PI * 0.5,
		}
	else:
		var size: Vector3 = spec.get("size", Vector3(4, 6, 4))
		plan = {
			"kind": "box",
			"half_extents": Vector2(size.x * 0.5, size.z * 0.5),
			"faces": _wall_faces(size),
			"front_n": Vector3(0, 0, 1),
		}

## The silhouette profile control points. These tables mirror the *_mesh construction constants in
## BaseShapeBuilder (the old massing_radius_at breakpoints; curves sampled piecewise-linear) — the
## survey is the READ surface; per-building rebuilds re-derive both from the plate.
func _survey_profile() -> void:
	profile.clear()
	var h := _height_total()
	var crown := float(datums["crown"])
	var comp := str(spec.get("composite", ""))
	if _is_drum():
		var r := float(spec.get("radius", 2.0))
		match comp:
			"plumbing_lobed":
				# the profile IS the lathe ring table's crest line (one authority: PLUMBING.rings)
				_profile_from_rings(table_for(spec, "plumbing")["rings"] as Array, h, crown)
			"ancourage_domes":
				# one continuous kiosk loft: body / rolled brim / 2-lobe dome (ANCOURAGE.rings)
				_profile_from_rings(table_for(spec, "ancourage")["rings"] as Array, h, crown)
			"hypelines_mound":
				# one continuous mound loft (one authority: HYPELINES.rings)
				_profile_from_rings(table_for(spec, "hypelines")["rings"] as Array, h, crown)
			"beacon_domed":
				# the bell-jar profile IS the ring table (one authority: BEACON.rings)
				for row_b in (table_for(spec, "beacon")["rings"] as Array):
					var rb2 := row_b as Array
					_pr(float(rb2[0]) * h, float(rb2[1]) * h)
				_pr(crown, 0.02 * h)
			_:
				var tiers := maxi(1, int(spec.get("tiers", 1)))
				if tiers > 1:
					var band := h / float(tiers)
					var inset := float(spec.get("tier_inset", 0.16))
					for k in range(tiers):
						var rk := maxf(0.4, r * (1.0 - inset * float(k)))
						_pr(band * float(k), rk)
						_pr(band * float(k + 1), rk)
				else:
					_pr(0.0, r)
					_pr(crown, r)
	else:
		var size: Vector3 = spec.get("size", Vector3(4, 6, 4))
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		match comp:
			"zone3_split":
				_pb(0.0, hx, hz)                          # main block plan W x 0.9W (plate ratio)
				_pb(h * 0.94, hx, hz)
				_pb(h * 0.94, hx + size.x * 0.09, hz + size.x * 0.09)   # cornice slab overhang (0.09W)
				_pb(crown, hx + size.x * 0.09, hz + size.x * 0.09)
			"open_files_awnings":
				# stepped awning flare approximated as a straight taper ground->core; the layout is
				# the construction authority (BaseShapeBuilder._awning_layout) — task-1 re-derives
				var core: Vector2 = BaseShapeBuilder._awning_layout(spec)["core"]
				_pb(0.0, hx, hz)
				_pb(crown, core.x, core.y)
			_:
				var tiers := maxi(1, int(spec.get("tiers", 1)))
				if tiers > 1:
					var band := h / float(tiers)
					var inset := float(spec.get("tier_inset", 0.16))
					for k in range(tiers):
						var f := maxf(0.25, 1.0 - inset * float(k))
						_pb(band * float(k), hx * f, hz * f)
						_pb(band * float(k + 1), hx * f, hz * f)
				else:
					_pb(0.0, hx, hz)
					_pb(crown, hx, hz)

func _pr(y: float, r: float) -> void:
	profile.append({"y": y, "r": r})

# the crest line of a survey lathe ring table [y, r, amp] (fractions of h) + the crown cap apex
func _profile_from_rings(rows: Array, h: float, crown: float) -> void:
	for row in rows:
		var rr := row as Array
		_pr(float(rr[0]) * h, float(rr[1]) * (1.0 + float(rr[2])) * h)
	_pr(crown, 0.01 * h)

func _pb(y: float, hx: float, hz: float) -> void:
	profile.append({"y": y, "hx": hx, "hz": hz})

## RESERVATIONS: openings (the door placements), the declared lattice's field claim, and decoration
## bands the massing wears (greenfields' slab rings). A lattice field lists the openings it is
## restructured around in `keeps_clear`; anything else overlapping an opening is a validation error.
func _survey_reservations(placements: Array) -> void:
	reservations.clear()
	var opening_ids: Array = []
	for pl_v in placements:
		var region := ((pl_v as Dictionary)["region"] as Dictionary)
		reservations.append(region)
		opening_ids.append(str(region["id"]))
	var eave := float(datums["eave"])
	var crown := float(datums["crown"])
	match str(spec.get("lattice", "")):
		"tracery":
			reservations.append({
				"id": "field_tracery", "type": "lattice_field", "cyl": true,
				"theta": 0.0, "half_arc": PI,
				"y0": 0.0, "y1": float(spec.get("tracery_height", spec.get("height", crown))),
				"keeps_clear": opening_ids,
			})
		"honeyframe", "voronoi", "rackwork":
			for f_v in _wall_faces(spec.get("size", Vector3(4, 6, 4))):
				var f := f_v as Dictionary
				reservations.append({
					"id": "field_%s_%s" % [str(spec.get("lattice", "")), _n_name(f["n"] as Vector3)],
					"type": "lattice_field", "cyl": false, "n": f["n"],
					"x_center": 0.0, "half_w": float(f["w"]) * 0.5,
					"y0": 0.0, "y1": crown,
					"keeps_clear": opening_ids,
				})
		"balconies":
			# greenfields: the balcony lattice LIVES on the slab-ring datums — ring bands, not wall
			# fields. keeps_clear stays EMPTY: a ring crossing a doorway is a real collision (the
			# door heights were reconciled at the survey to fit under the first ring).
			var storeys: Array = datums["storeys"]
			for k in range(storeys.size()):
				var y := minf(float(storeys[k]), crown - 0.09)
				reservations.append({
					"id": "slab_ring_%d" % k, "type": "lattice_field", "ring": true,
					"y0": y - 0.09, "y1": y + 0.09, "keeps_clear": [],
				})
			# the arcade band (arches + doors + sconces, an ensemble with every placed door), the
			# per-storey window bands (clear of the sign below and the next ring above), the sign
			var g: Dictionary = table_for(spec, "greenfields")
			reservations.append({"id": "arcade", "type": "decoration", "ring": true,
				"y0": 0.0, "y1": float((g["arcade"] as Dictionary)["apex"]) + 0.1,
				"keeps_clear": opening_ids})
			var ground := float(storeys[0])
			var band := float(storeys[1]) - ground
			for fl in range(storeys.size() - 1):
				var base := ground + band * float(fl)
				reservations.append({"id": "window_band_%d" % fl, "type": "decoration", "ring": true,
					"y0": base + band * float((g["window"] as Dictionary)["band_y0"]),
					"y1": base + band * float((g["window"] as Dictionary)["band_y1"]),
					"keeps_clear": ["sign_board"]})
			var sgn2: Dictionary = g["sign"]
			reservations.append({"id": "sign_board", "type": "decoration", "cyl": false,
				"n": Vector3(0, 0, 1), "x_center": 0.0, "half_w": float(sgn2["w"]) * 0.5,
				"y0": float(sgn2["y0"]), "y1": float(sgn2["y1"]),
				"keeps_clear": ["slab_ring_0"]})   # the board is mounted riding the first slab band
	if str(spec.get("composite", "")) == "canopy_piers":
		# the canopy slab band: nothing else may claim the air the slab occupies — the fascia
		# fixtures (title sign, corner perforations) are declared ensembles riding ON it
		reservations.append({
			"id": "canopy_slab", "type": "decoration", "ring": true,
			"y0": eave, "y1": crown, "keeps_clear": ["fascia_sign", "perf_left", "perf_right"],
		})
		var cs2: Dictionary = table_for(spec, "cleanstreets")
		var sgn: Dictionary = cs2["sign"]
		reservations.append({"id": "fascia_sign", "type": "decoration", "cyl": false,
			"n": Vector3(0, 0, 1), "x_center": 0.0, "half_w": float(sgn["w"]) * 0.5,
			"y0": float(sgn["y0"]), "y1": float(sgn["y1"]), "keeps_clear": []})
		var perf: Dictionary = cs2["perf"]
		for px in [-1.0, 1.0]:
			reservations.append({"id": "perf_left" if px < 0.0 else "perf_right",
				"type": "decoration", "cyl": false, "n": Vector3(0, 0, 1),
				"x_center": float(perf["x_center"]) * px, "half_w": float(perf["half_w"]),
				"y0": float(perf["y0"]), "y1": float(perf["y1"]), "keeps_clear": []})
		var toll: Dictionary = cs2["toll"]
		reservations.append({"id": "toll_header", "type": "decoration", "cyl": false,
			"n": Vector3(1, 0, 0), "x_center": float(spec.get("door_lateral", 0.0)),
			"half_w": float(toll["header_w"]) * 0.5,
			"y0": float(toll["header_y0"]), "y1": float(toll["header_y1"]),
			"keeps_clear": ["door_main"]})
	if str(spec.get("composite", "")) == "plumbing_lobed":
		_plumbing_reservations()
	if str(spec.get("composite", "")) == "hypelines_mound":
		_hypelines_reservations()
	if str(spec.get("composite", "")) == "ancourage_domes":
		_ancourage_reservations()
	if str(spec.get("composite", "")) == "beacon_domed":
		_beacon_reservations()
	if str(spec.get("composite", "")) == "bulwark_towers":
		_bulwark_reservations()
	if str(spec.get("composite", "")) == "zone3_split":
		_zone3_reservations()
	if str(spec.get("kind", "")) == "honeycomb_cooperative":
		_honeycomb_reservations()
	if str(spec.get("composite", "")) == "open_files_awnings":
		_open_files_reservations()

## Every planned open-files part claims its wall: the nested portal surround (an ensemble with
## the opening), the glowing sign + heraldic crest (the rackwork field restructures around both),
## and the layer-1 proud pieces (console pedestals, fin sconces). The scan-beam fan and bollards
## ride the apron ground and claim no wall.
func _open_files_reservations() -> void:
	var tbl := table_for(spec, "open_files")
	var fz := Vector3(0, 0, 1)
	var po: Dictionary = tbl["portal"]
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.5))
	var door_h := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.2))
	var p_reach := float(po["frames"]) * float(po["frame_step"])
	reservations.append({"id": "portal_surround", "type": "decoration", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": door_w * 0.5 + p_reach + 0.15,
		"y0": 0.0, "y1": door_h + p_reach + 0.20, "keeps_clear": ["door_main"]})
	var sgn: Dictionary = tbl["sign"]
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(sgn["w"]) * 0.5,
		"y0": float(sgn["y0"]), "y1": float(sgn["y1"]), "keeps_clear": []})
	var cr: Dictionary = tbl["crest"]
	reservations.append({"id": "crest", "type": "decoration", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(cr["w"]) * 0.5,
		"y0": float(cr["y0"]), "y1": float(cr["y1"]), "keeps_clear": []})
	for r_v in reservations:
		var rv := r_v as Dictionary
		if str(rv.get("id", "")) == "field_rackwork_front":
			(rv["keeps_clear"] as Array).append("sign_board")
			(rv["keeps_clear"] as Array).append("crest")
			(rv["keeps_clear"] as Array).append("portal_surround")
	for cx_v in (tbl["consoles"] as Dictionary)["xs"]:
		reservations.append({"id": "console_%s" % ("r" if float(cx_v) > 0.0 else "l"),
			"type": "decoration", "layer": 1, "cyl": false, "n": fz,
			"x_center": float(cx_v), "half_w": 0.35, "y0": 0.0, "y1": 1.4, "keeps_clear": []})
	var scn: Dictionary = tbl["sconces"]
	for sx_v in (scn["xs"] as Array):
		for sy_v in (scn["ys"] as Array):
			reservations.append({"id": "sconce_%s_%d" % ["r" if float(sx_v) > 0.0 else "l", int(float(sy_v) * 10.0)],
				"type": "decoration", "layer": 1, "cyl": false, "n": fz,
				"x_center": float(sx_v), "half_w": 0.12,
				"y0": float(sy_v) - 0.15, "y1": float(sy_v) + 0.15, "keeps_clear": []})

## Every planned honeycomb part claims its wall. The intact faces: the honeyframe FIELD (generic)
## + one cell-fixtures band per face (vents/planters ride the engine's real cell rects — the band
## and the field declare each other) + the hex sign cell. The TORN +X flank: its field reservation
## is REMOVED (the frame is skipped there) and replaced by the hole, three layer-1 catwalk rows
## and the rust wash (catwalks and wash declare each other). Entry fixtures are layer-1 proud.
func _honeycomb_reservations() -> void:
	var tbl := table_for(spec, "honeycomb")
	var h := _height_total()
	var fz := Vector3(0, 0, 1)
	# the torn flank loses its honeyframe field (skip_faces leaves the face bare)
	for ri in range(reservations.size() - 1, -1, -1):
		if str((reservations[ri] as Dictionary).get("id", "")) == "field_honeyframe_right":
			reservations.remove_at(ri)
	var sizeh: Vector3 = spec.get("size", Vector3(4.5, 10.0, 6.3))
	for face_pair in [[fz, "front", sizeh.x], [Vector3(-1, 0, 0), "left", sizeh.z], [Vector3(0, 0, -1), "back", sizeh.z]]:
		var fp := face_pair as Array
		var fid := "cell_fixtures_%s" % str(fp[1])
		reservations.append({"id": fid, "type": "decoration", "cyl": false, "n": fp[0],
			"x_center": 0.0, "half_w": float(fp[2]) * 0.5 - 0.05,
			"y0": 0.02 * h, "y1": 0.96 * h,
			"keeps_clear": ["field_honeyframe_%s" % str(fp[1]), "sign_cell", "door_main"]})
		for r_v in reservations:
			var rv := r_v as Dictionary
			if str(rv.get("id", "")) == "field_honeyframe_%s" % str(fp[1]):
				(rv["keeps_clear"] as Array).append(fid)
				(rv["keeps_clear"] as Array).append("sign_cell")
	var sc: Dictionary = tbl["sign_cell"]
	reservations.append({"id": "sign_cell", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(sc["x"]) * h, "half_w": float(sc["half_w"]) * h,
		"y0": float(sc["y0"]) * h, "y1": float(sc["y1"]) * h,
		"keeps_clear": ["field_honeyframe_front", "cell_fixtures_front"]})
	# the torn flank: hole (wall skin) + catwalk rows and rust wash (proud crust, declared pair)
	var hole: Dictionary = tbl["hole"]
	reservations.append({"id": "torn_hole", "type": "decoration", "cyl": false, "n": Vector3(1, 0, 0),
		"x_center": float(hole["z"]) * h, "half_w": float(hole["half_w"]) * h,
		"y0": float(hole["y0"]) * h, "y1": float(hole["y1"]) * h, "keeps_clear": []})
	var cw: Dictionary = tbl["catwalks"]
	var cw_ids: Array = []
	var rows: Array = cw["rows"]
	for k in range(rows.size()):
		cw_ids.append("catwalk_%d" % k)
	for k2 in range(rows.size()):
		reservations.append({"id": "catwalk_%d" % k2, "type": "decoration", "layer": 1,
			"cyl": false, "n": Vector3(1, 0, 0), "x_center": 0.0,
			"half_w": sizeh.z * 0.5 - 0.05,
			"y0": float(rows[k2]) * h, "y1": (float(rows[k2]) + float(cw["rail_h"]) + 0.012) * h,
			"keeps_clear": ["rust_wash"]})
	reservations.append({"id": "rust_wash", "type": "decoration", "layer": 1, "cyl": false,
		"n": Vector3(1, 0, 0), "x_center": 0.0, "half_w": sizeh.z * 0.5 - 0.05,
		"y0": 0.05 * h, "y1": 0.90 * h, "keeps_clear": cw_ids})
	# entry fixtures: proud layer-1 pieces around the doorway (transom, sconces, kiosk, planters)
	var en: Dictionary = tbl["entry"]
	var door_h := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.7))
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.6))
	reservations.append({"id": "transom", "type": "decoration", "layer": 1, "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": door_w * 0.5 + 0.15,
		"y0": door_h + 0.05, "y1": door_h + 0.05 + float(en["transom_h"]), "keeps_clear": []})
	for so in [1.0, -1.0]:
		reservations.append({"id": "sconce_%s" % ("r" if so > 0.0 else "l"), "type": "decoration",
			"layer": 1, "cyl": false, "n": fz,
			"x_center": so * (door_w * 0.5 + float(en["sconce_off"]) - 0.6), "half_w": 0.12,
			"y0": float(en["sconce_y"]) - 0.15, "y1": float(en["sconce_y"]) + 0.15, "keeps_clear": []})
	reservations.append({"id": "entry_kiosk", "type": "decoration", "layer": 1, "cyl": false,
		"n": fz, "x_center": float(en["kiosk_x"]), "half_w": 0.22,
		"y0": 0.0, "y1": 1.35, "keeps_clear": []})
	for pxi in range(2):
		reservations.append({"id": "entry_planter_%d" % pxi, "type": "decoration", "layer": 1,
			"cyl": false, "n": fz, "x_center": float((en["planters_x"] as Array)[pxi]),
			"half_w": 0.24, "y0": 0.0, "y1": 0.5, "keeps_clear": []})

## Every planned zone3 part claims its wall: the siding band + shop window (a declared pair),
## the sign, the upper windows (front + side), the torn wing's cavity galleries, and the layer-1
## crust (porch shelter, terminal cabinet, corner root climbs, cornice drip band — proud parts
## that legally bridge the wall skin; drips and climbs declare each other where they cross).
func _zone3_reservations() -> void:
	var tbl := table_for(spec, "zone3")
	var h := _height_total()
	var fz := Vector3(0, 0, 1)
	var sd: Dictionary = tbl["siding"]
	var main_c := (float(tbl["main_x0"]) + float(tbl["main_x1"])) * 0.5
	var main_hw := (float(tbl["main_x1"]) - float(tbl["main_x0"])) * 0.5
	reservations.append({"id": "siding_band", "type": "decoration", "cyl": false, "n": fz,
		"x_center": main_c * h, "half_w": main_hw * h,
		"y0": 0.0, "y1": float(sd["y1"]) * h, "keeps_clear": ["door_main", "shop_window"]})
	var sw: Dictionary = tbl["shop_window"]
	reservations.append({"id": "shop_window", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(sw["x"]) * h, "half_w": float(sw["half_w"]) * h,
		"y0": float(sw["y0"]) * h, "y1": float(sw["y1"]) * h, "keeps_clear": ["siding_band"]})
	var sgn: Dictionary = tbl["sign"]
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(sgn["x"]) * h, "half_w": float(sgn["half_w"]) * h,
		"y0": float(sgn["y0"]) * h, "y1": float(sgn["y1"]) * h, "keeps_clear": []})
	var wins: Array = tbl["windows"]
	for i in range(wins.size()):
		var wn := wins[i] as Array
		reservations.append({"id": "window_%d" % i, "type": "decoration", "cyl": false, "n": fz,
			"x_center": float(wn[0]) * h, "half_w": float(wn[1]) * h,
			"y0": float(wn[2]) * h, "y1": float(wn[3]) * h, "keeps_clear": []})
	var swins: Array = tbl["side_windows"]
	for i2 in range(swins.size()):
		var wn2 := swins[i2] as Array
		reservations.append({"id": "side_window_%d" % i2, "type": "decoration", "cyl": false,
			"n": Vector3(-1, 0, 0), "x_center": float(wn2[0]) * h, "half_w": float(wn2[1]) * h,
			"y0": float(wn2[2]) * h, "y1": float(wn2[3]) * h, "keeps_clear": []})
	# the torn wing's open cavity galleries (between the floor slab datums)
	var slabs: Array = tbl["slabs"]
	var slab_t := float(tbl["slab_t"])
	var wing_c := (float(tbl["main_x1"]) + float(tbl["wing_x1"])) * 0.5
	var prev_top := 0.045
	for k in range(slabs.size() + 1):
		var band_top := (float(slabs[k]) - slab_t * 0.5) if k < slabs.size() else float(tbl["cornice_y"]) - 0.02
		if band_top - prev_top > 0.06:
			reservations.append({"id": "cavity_%d" % k, "type": "decoration", "cyl": false, "n": fz,
				"x_center": wing_c * h, "half_w": float(tbl["cavity_half_w"]) * h,
				"y0": prev_top * h, "y1": band_top * h, "keeps_clear": ["door_main"]})
		if k < slabs.size():
			prev_top = float(slabs[k]) + slab_t * 0.5
	# layer-1 crust: the porch shelter, the terminal cabinet, corner root climbs, the drip band
	var po: Dictionary = tbl["porch"]
	reservations.append({"id": "porch_row", "type": "decoration", "layer": 1, "cyl": false, "n": fz,
		"x_center": main_c * h, "half_w": main_hw * h,
		"y0": 0.0, "y1": float(po["y_wall"]) * h,
		"keeps_clear": ["root_climb_0", "root_climb_1", "root_climb_2"]})
	var tm: Dictionary = tbl["terminal"]
	reservations.append({"id": "terminal_cabinet", "type": "decoration", "layer": 1, "cyl": false,
		"n": fz, "x_center": float(tm["x"]) * h, "half_w": float(tm["half_w"]) * h,
		"y0": 0.0, "y1": float(tm["y1"]) * h, "keeps_clear": []})
	var td: Dictionary = tbl["tendrils"]
	var climb_ids: Array = []
	for c in range(int(td["climbs"])):
		var cid := "root_climb_%d" % c
		climb_ids.append(cid)
		var cx: float = float([-0.345, 0.345, -0.30][c % 3])
		reservations.append({"id": cid, "type": "decoration", "layer": 1, "cyl": false,
			"n": fz if c < 2 else Vector3(-1, 0, 0),
			"x_center": float(cx) * h, "half_w": 0.022 * h,
			"y0": 0.0, "y1": float(tbl["cornice_y"]) * h,
			"keeps_clear": ["drip_band", "porch_row"]})
	reservations.append({"id": "drip_band", "type": "decoration", "layer": 1, "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(tbl["wing_x1"]) * h,
		"y0": 0.88 * h, "y1": float(tbl["cornice_y"]) * h, "keeps_clear": climb_ids})

## Every planned bulwark part claims its wall: the framed MEMBRANE field (the voronoi web
## restructures around the rose, pores and weep it lists in keeps_clear), the sign band, the
## readout/indicator/kiosk boards, the door surround (the vault idiom, an ensemble with the
## opening), tower engagement strips at every corner, and the wing attachment bands. The wings
## also register barrier_wing SOCKETS (reach — their tips run legally past the envelope).
func _bulwark_reservations() -> void:
	var tbl := table_for(spec, "bulwark")
	var h := _height_total()
	var size: Vector3 = spec.get("size", Vector3(4.6, 5.2, 3.4))
	var fz := Vector3(0, 0, 1)
	var fr_t: Dictionary = tbl["frame"]
	var rose: Dictionary = tbl["rose"]
	var pores: Array = tbl["pores"]
	var weep: Dictionary = tbl["weep"]
	var membrane_kc: Array = ["rose_aperture", "rust_weep"]
	reservations.append({"id": "rose_aperture", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(rose["x"]) * h, "half_w": float(rose["r"]) * h,
		"y0": (float(rose["y"]) - float(rose["r"])) * h, "y1": (float(rose["y"]) + float(rose["r"])) * h,
		"keeps_clear": []})
	for i in range(pores.size()):
		var pr := pores[i] as Array
		reservations.append({"id": "pore_%d" % i, "type": "decoration", "cyl": false, "n": fz,
			"x_center": float(pr[0]) * h, "half_w": float(pr[2]) * h,
			"y0": (float(pr[1]) - float(pr[2])) * h, "y1": (float(pr[1]) + float(pr[2])) * h,
			"keeps_clear": []})
		membrane_kc.append("pore_%d" % i)
	reservations.append({"id": "rust_weep", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(weep["x"]) * h, "half_w": float(weep["half_w"]) * h,
		"y0": float(weep["y0"]) * h, "y1": float(weep["y1"]) * h,
		"keeps_clear": ["sign_board"]})
	reservations.append({"id": "framed_membrane", "type": "lattice_field", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(fr_t["half_w"]) * h,
		"y0": float(fr_t["y0"]) * h, "y1": float(fr_t["y1"]) * h,
		"keeps_clear": membrane_kc})
	var sgn: Dictionary = tbl["sign"]
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(sgn["half_w"]) * h,
		"y0": float(sgn["y0"]) * h, "y1": float(sgn["y1"]) * h, "keeps_clear": ["rust_weep"]})
	var rd: Dictionary = tbl["readout"]
	reservations.append({"id": "readout_panel", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(rd["x"]) * h, "half_w": float(rd["half_w"]) * h,
		"y0": float(rd["y0"]) * h, "y1": float(rd["y1"]) * h, "keeps_clear": []})
	var ind: Dictionary = tbl["indicator"]
	reservations.append({"id": "indicator_lamp", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(ind["x"]) * h, "half_w": float(ind["half_w"]) * h,
		"y0": float(ind["y0"]) * h, "y1": float(ind["y1"]) * h, "keeps_clear": []})
	var ki: Dictionary = tbl["kiosk"]
	reservations.append({"id": "console_kiosk", "type": "decoration", "cyl": false, "n": fz,
		"x_center": float(ki["x"]) * h, "half_w": float(ki["half_w"]) * h,
		"y0": 0.0, "y1": float(ki["y1"]) * h, "keeps_clear": []})
	var door_t: Dictionary = tbl["door"]
	reservations.append({"id": "door_surround", "type": "decoration", "cyl": false, "n": fz,
		"x_center": 0.0, "half_w": float(door_t["surround_half_w"]) * h,
		"y0": 0.0, "y1": float(door_t["surround_top"]) * h,
		"keeps_clear": ["door_main", "console_kiosk", "indicator_lamp"]})
	# tower engagement strips: each corner tower kisses BOTH its adjacent faces
	var eave := float(datums["eave"])
	var t_r := float((tbl["tower"] as Dictionary)["r"]) * h
	for sn in [1.0, -1.0]:
		for sx in [1.0, -1.0]:
			reservations.append({"id": "tower_z%s_x%s" % ["p" if sn > 0.0 else "n", "p" if sx > 0.0 else "n"],
				"type": "decoration", "cyl": false, "n": Vector3(0, 0, sn),
				"x_center": sx * (size.x * 0.5 - t_r * 0.35), "half_w": t_r * 0.35,
				"y0": 0.0, "y1": eave, "keeps_clear": []})
			reservations.append({"id": "tower_x%s_z%s" % ["p" if sn > 0.0 else "n", "p" if sx > 0.0 else "n"],
				"type": "decoration", "cyl": false, "n": Vector3(sn, 0, 0),
				"x_center": sx * (size.z * 0.5 - t_r * 0.35), "half_w": t_r * 0.35,
				"y0": 0.0, "y1": eave, "keeps_clear": []})
	# wing attachment bands + the barrier_wing sockets (reach: tips run past the envelope)
	var wg: Dictionary = tbl["wing"]
	for sx2 in [1.0, -1.0]:
		reservations.append({"id": "wing_attach_%s" % ("p" if sx2 > 0.0 else "n"),
			"type": "decoration", "cyl": false, "n": Vector3(sx2, 0, 0),
			"x_center": float(wg["lateral"]) * h, "half_w": float(wg["attach_half_w"]) * h,
			"y0": 0.058 * h, "y1": float(wg["panel_h"]) * h, "keeps_clear": []})

## Every planned beacon part claims its wall: the FIVE great arch bays (the tracery restructures
## around them — the lancet field lists them in keeps_clear and only populates unreserved arcs),
## the cartouche riding the portal (the door's idiom), the status board, the enforcement
## vestibule, the dome oculi. The lantern ring and beds are crown/ground features.
func _beacon_reservations() -> void:
	var tbl := table_for(spec, "beacon")
	var h := _height_total()
	var fr := PI * 0.5
	var bay_ids: Array = []
	var bays: Array = tbl["bays"]
	for i in range(bays.size()):
		var b := bays[i] as Array
		# the right bays NEST the enforcement vestibule under their arches (the plate's
		# composition) — a declared ensemble, not a collision
		reservations.append({"id": "great_bay_%d" % i, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(b[0]), -PI, PI), "half_arc": float(tbl["bay_half_arc"]),
			"y0": float(b[1]) * h, "y1": float(b[2]) * h,
			"keeps_clear": ["enforcement_vestibule"]})
		bay_ids.append("great_bay_%d" % i)
	# the rear lancet tracery keeps clear of every great bay AND the doors (reserved arcs)
	for r_v in reservations:
		if str((r_v as Dictionary).get("id", "")) == "field_tracery":
			var kc := ((r_v as Dictionary)["keeps_clear"] as Array)
			for bid in bay_ids:
				kc.append(bid)
			# the lancet field also restructures around the ground fixtures + dome oculi
			for fid in ["cartouche", "status_board", "enforcement_vestibule",
					"oculus_0", "oculus_1", "oculus_2", "oculus_3"]:
				kc.append(fid)
	var car: Dictionary = tbl["cartouche"]
	reservations.append({"id": "cartouche", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": float(car["w"]) * 0.5 / maxf(0.3, float(plan.get("wall_radius", 2.7))),
		"y0": float(car["y0"]) * h, "y1": float(car["y1"]) * h,
		"keeps_clear": ["door_main"]})
	var st2: Dictionary = tbl["status"]
	reservations.append({"id": "status_board", "type": "decoration", "cyl": true,
		"theta": wrapf(fr + float(st2["az"]), -PI, PI),
		"half_arc": float(st2["w"]) * 0.5 / maxf(0.3, float(plan.get("wall_radius", 2.7))),
		"y0": float(st2["y0"]) * h, "y1": float(st2["y1"]) * h, "keeps_clear": []})
	var ve: Dictionary = tbl["vestibule"]
	reservations.append({"id": "enforcement_vestibule", "type": "decoration", "cyl": true,
		"theta": wrapf(fr + float(ve["az"]), -PI, PI),
		"half_arc": (float(ve["w"]) * 0.5 + 0.08) / maxf(0.3, float(plan.get("wall_radius", 2.7))),
		"y0": 0.0, "y1": float(ve["plaque_y1"]) + 0.1, "keeps_clear": []})
	var ocs: Array = tbl["oculi"]
	for i2 in range(ocs.size()):
		var oc := ocs[i2] as Array
		reservations.append({"id": "oculus_%d" % i2, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(oc[0]), -PI, PI),
			"half_arc": 0.30 / maxf(0.3, radius_at(float(oc[1]) * h)),
			"y0": float(oc[1]) * h - 0.16, "y1": float(oc[1]) * h + 0.16, "keeps_clear": []})

## Every planned ancourage part claims its wall: the grand arch + glass + readout are the door's
## declared ensemble; placards, roses, louver, pores, engaged pipes and valves each claim their arc.
func _ancourage_reservations() -> void:
	var tbl := table_for(spec, "ancourage")
	var h := _height_total()
	var fr := PI * 0.5
	var arch: Dictionary = tbl["arch"]
	var wall_r := float(plan.get("wall_radius", 2.25))
	reservations.append({"id": "entry_arch", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": (float(arch["w"]) * 0.5 + float(arch["r_tube"])) / maxf(0.3, wall_r),
		"y0": 0.0, "y1": float(arch["apex"]) + 0.1,
		"keeps_clear": ["door_main", "arch_glass", "readout"]})
	reservations.append({"id": "arch_glass", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": float(arch["w"]) * 0.45 / maxf(0.3, wall_r),
		"y0": float(arch["glass_y0"]), "y1": float(arch["glass_y1"]),
		"keeps_clear": ["door_main", "entry_arch"]})
	reservations.append({"id": "readout", "type": "decoration", "cyl": true,
		"theta": fr + float(tbl["readout"]["off"]) / maxf(0.3, wall_r) * 1.6,
		"half_arc": 0.14 / maxf(0.3, wall_r),
		"y0": 0.0, "y1": float(tbl["readout"]["h"]),
		"keeps_clear": ["door_main", "entry_arch"]})
	var sign: Dictionary = tbl["sign"]
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": float(sign["w"]) * 0.5 / maxf(0.3, radius_at((float(sign["y0"]) + float(sign["y1"])) * 0.5 * h)),
		"y0": float(sign["y0"]) * h, "y1": float(sign["y1"]) * h, "keeps_clear": []})
	var ppp: Dictionary = tbl["ppp"]
	reservations.append({"id": "ppp_placard", "type": "decoration", "cyl": true,
		"theta": wrapf(fr + float(ppp["az"]), -PI, PI),
		"half_arc": float(ppp["w"]) * 0.5 / maxf(0.3, wall_r),
		"y0": float(ppp["y0"]) * h, "y1": float(ppp["y1"]) * h, "keeps_clear": []})
	var roses: Array = tbl["roses"]
	for i in range(roses.size()):
		var ro := roses[i] as Array
		var rmid := (float(ro[1]) + float(ro[2])) * 0.5 * h
		reservations.append({"id": "rose_%d" % i, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(ro[0]), -PI, PI),
			"half_arc": float(ro[3]) * h * 0.55 / maxf(0.3, radius_at(rmid)),
			"y0": float(ro[1]) * h, "y1": float(ro[2]) * h, "keeps_clear": []})
	var lou: Dictionary = tbl["louver"]
	if float(lou["w"]) > 0.01:
		reservations.append({"id": "louver", "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(lou["az"]), -PI, PI),
			"half_arc": float(lou["w"]) * h * 0.55 / maxf(0.3, radius_at((float(lou["y0"]) + float(lou["y1"])) * 0.5 * h)),
			"y0": float(lou["y0"]) * h, "y1": float(lou["y1"]) * h, "keeps_clear": []})
	var pores: Array = tbl["pores"]
	for i2 in range(pores.size()):
		var po := pores[i2] as Array
		reservations.append({"id": "dome_pore_%d" % i2, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(po[0]), -PI, PI),
			"half_arc": float(po[3]) * h * 0.6 / maxf(0.3, radius_at((float(po[1]) + float(po[2])) * 0.5 * h)),
			"y0": float(po[1]) * h, "y1": float(po[2]) * h, "keeps_clear": []})
	var eng: Dictionary = tbl["engaged"]
	var eng_azs: Array = eng["azs"]
	for i3 in range(eng_azs.size()):
		reservations.append({"id": "engaged_pipe_%d" % i3, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(eng_azs[i3]), -PI, PI),
			"half_arc": (float(eng["r"]) * h + 0.05) / maxf(0.3, wall_r),
			"y0": 0.0, "y1": 0.46 * h, "keeps_clear": []})
	var whl: Dictionary = tbl["wheel"]
	reservations.append({"id": "wheel_valve", "type": "decoration", "cyl": true,
		"theta": wrapf(fr + float(whl["az"]), -PI, PI),
		"half_arc": float(whl["dia"]) * h * 0.55 / maxf(0.3, wall_r),
		"y0": (float(whl["y"]) - float(whl["dia"]) * 0.55) * h,
		"y1": (float(whl["y"]) + float(whl["dia"]) * 0.55) * h, "keeps_clear": []})
	var rst: Dictionary = tbl["rosette"]
	reservations.append({"id": "rosette_port", "type": "decoration", "cyl": true,
		"theta": wrapf(fr + float(rst["az"]), -PI, PI),
		"half_arc": float(rst["dia"]) * h * 0.55 / maxf(0.3, wall_r),
		"y0": (float(rst["y"]) - float(rst["dia"]) * 0.55) * h,
		"y1": (float(rst["y"]) + float(rst["dia"]) * 0.55) * h, "keeps_clear": []})

## Every planned hypelines part claims its wall before meshing: the six arm roots, the sign stack
## (sign / ghost letters / toll board), the entry arch, the valve wheel, pores and the dome vent.
func _hypelines_reservations() -> void:
	var tbl := table_for(spec, "hypelines")
	var h := _height_total()
	var fr := PI * 0.5
	var arms: Array = tbl["arms"]
	for i in range(arms.size()):
		var a := arms[i] as Dictionary
		var cy := float(a["attach"]) * h
		var pr := float(a["pipe_r"])
		reservations.append({"id": "arm_root_%d" % i, "type": "socket", "cyl": true,
			"theta": wrapf(fr + float(a["az"]), -PI, PI),
			"half_arc": (pr + 0.06) / maxf(0.3, radius_at(cy)),
			"y0": cy - pr - 0.06, "y1": cy + pr + 0.06, "keeps_clear": []})
	var sign: Dictionary = tbl["sign"]
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": float(sign["w"]) * 0.5 / maxf(0.3, radius_at((float(sign["y0"]) + float(sign["y1"])) * 0.5 * h)),
		"y0": float(sign["y0"]) * h, "y1": float(sign["y1"]) * h, "keeps_clear": []})
	var ghost: Dictionary = tbl["ghost"]
	if float(ghost["w"]) > 0.05:
		reservations.append({"id": "ghost_letters", "type": "decoration", "cyl": true, "theta": fr,
			"half_arc": float(ghost["w"]) * 0.5 / maxf(0.3, radius_at((float(ghost["y0"]) + float(ghost["y1"])) * 0.5 * h)),
			"y0": float(ghost["y0"]) * h, "y1": float(ghost["y1"]) * h, "keeps_clear": []})
	var toll: Dictionary = tbl["toll"]
	reservations.append({"id": "toll_board", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": float(toll["w"]) * 0.5 / maxf(0.3, float(plan.get("wall_radius", 1.5))),
		"y0": float(toll["y0"]) * h, "y1": float(toll["y1"]) * h,
		"keeps_clear": ["door_main"]})   # the toll board hangs in the arch, over the doorway
	var arch: Dictionary = tbl["arch"]
	reservations.append({"id": "entry_arch", "type": "decoration", "cyl": true, "theta": fr,
		"half_arc": (float(arch["w"]) * 0.5 + float(arch["r_tube"])) / maxf(0.3, float(plan.get("wall_radius", 1.5))),
		"y0": 0.0, "y1": float(arch["y_top"]) * h,
		"keeps_clear": ["door_main", "toll_board"]})   # the arch IS the door's idiom, toll board inside it
	var wheel: Dictionary = tbl["wheel"]
	var wy := float(wheel["y"]) * h
	reservations.append({"id": "valve_wheel", "type": "decoration", "cyl": true,
		"theta": fr + float(wheel["az"]),
		"half_arc": float(wheel["dia"]) * h * 0.55 / maxf(0.3, radius_at(wy)),
		"y0": wy - float(wheel["dia"]) * h * 0.55, "y1": wy + float(wheel["dia"]) * h * 0.55,
		"keeps_clear": []})
	var pores: Array = tbl["pores"]
	for i2 in range(pores.size()):
		var p := pores[i2] as Array
		var pmid := (float(p[1]) + float(p[2])) * 0.5 * h
		reservations.append({"id": "pore_%d" % i2, "type": "decoration", "cyl": true,
			"theta": wrapf(fr + float(p[0]), -PI, PI),
			"half_arc": float(p[3]) * h * 0.5 / maxf(0.3, radius_at(pmid)),
			"y0": float(p[1]) * h, "y1": float(p[2]) * h, "keeps_clear": []})
	var vent: Dictionary = tbl["vent"]
	reservations.append({"id": "dome_vent", "type": "decoration", "cyl": true,
		"theta": fr + float(vent["az"]),
		"half_arc": float(vent["w"]) * h * 0.5 / maxf(0.3, radius_at((float(vent["y0"]) + float(vent["y1"])) * 0.5 * h)) + 0.02,
		"y0": float(vent["y0"]) * h, "y1": float(vent["y1"]) * h, "keeps_clear": []})

## Every planned plumbing part claims its wall BEFORE meshing (the PLUMBING survey table). The
## flume's helix is claimed as stepped eighth-turn arc bands so the overlap check is meaningful.
func _plumbing_reservations() -> void:
	var tbl := table_for(spec, "plumbing")
	var h := _height_total()
	var fr := PI * 0.5   # the front axis
	var sl: Array = tbl["slits"]
	for i in range(sl.size()):
		var s := sl[i] as Array
		var ymid := (float(s[1]) + float(s[2])) * 0.5 * h
		reservations.append({"id": "slit_%d" % i, "type": "decoration", "cyl": true,
			"theta": fr + float(s[0]), "half_arc": float(s[3]) * h * 0.5 / maxf(0.3, radius_at(ymid)),
			"y0": float(s[1]) * h, "y1": float(s[2]) * h, "keeps_clear": []})
	var wh: Array = tbl["wheels"]
	for i in range(wh.size()):
		var w := w_row(wh[i])
		reservations.append({"id": "wheel_%d" % i, "type": "decoration", "cyl": true,
			"theta": fr + w.x, "half_arc": w.z * h * 0.5 / maxf(0.3, radius_at(w.y * h)),
			"y0": (w.y - w.z * 0.5) * h, "y1": (w.y + w.z * 0.5) * h, "keeps_clear": []})
	var stub := w_row(tbl["stub_wheel"])
	reservations.append({"id": "wheel_stub", "type": "decoration", "cyl": true,
		"theta": fr + stub.x, "half_arc": stub.z * h * 0.5 / maxf(0.3, radius_at(stub.y * h)),
		"y0": (stub.y - stub.z * 0.5) * h, "y1": (stub.y + stub.z * 0.5) * h, "keeps_clear": []})
	var sign: Dictionary = tbl["sign"]
	var sign_mid := (float(sign["y0"]) + float(sign["y1"])) * 0.5 * h
	reservations.append({"id": "sign_board", "type": "decoration", "cyl": true,
		"theta": fr + float(sign["theta_off"]),
		"half_arc": float(sign["w"]) * 0.5 / maxf(0.3, radius_at(sign_mid)),
		"y0": float(sign["y0"]) * h, "y1": float(sign["y1"]) * h, "keeps_clear": []})
	var hood: Dictionary = tbl["hood"]
	reservations.append({"id": "entry_hood", "type": "decoration", "cyl": true,
		"theta": fr + float(hood["theta_off"]),
		"half_arc": float(hood["w"]) * 0.5 / maxf(0.3, float(plan.get("wall_radius", 1.6))),
		"y0": 0.0, "y1": float(hood["ridge"]) * h,
		"keeps_clear": ["door_main"]})   # the hood IS the door's own architecture
	var casc: Dictionary = tbl["cascade"]
	reservations.append({"id": "cascade", "type": "decoration", "cyl": true,
		"theta": fr + float(casc["theta_off"]),
		"half_arc": float(casc["w"]) * 0.5 / maxf(0.3, radius_at(0.08 * h)),
		"y0": 0.0, "y1": float(casc["y_top"]) * h, "keeps_clear": []})
	var pipe: Dictionary = tbl["side_pipe"]
	reservations.append({"id": "side_pipe", "type": "decoration", "cyl": true,
		"theta": fr + float(pipe["theta_off"]),
		"half_arc": (float(pipe["dia"]) * 0.5 + 0.01) * h / maxf(0.3, radius_at(0.3 * h)),
		"y0": 0.0, "y1": float(pipe["y_top"]) * h, "keeps_clear": []})
	var ribs: Dictionary = tbl["ribs"]
	for k in range(int(ribs["count"])):
		var rth := fr + float(ribs["theta0_off"]) + TAU * float(k) / float(ribs["count"])
		reservations.append({"id": "dome_rib_%d" % k, "type": "decoration", "cyl": true,
			"theta": wrapf(rth, -PI, PI),
			"half_arc": (float(ribs["r"]) + 0.004) * h / maxf(0.3, radius_at(0.81 * h)),
			"y0": float(ribs["y0"]) * h, "y1": float(ribs["y1"]) * h, "keeps_clear": []})
	var fl: Dictionary = tbl["flume"]
	var arcs := int(round(float(fl["turns"]) * 8.0))   # eighth-turn claim bands, stepping down
	var band_up := (float(fl["depth"]) + float(fl["rail_h"]) + 0.01) * h   # floor -> rail top
	for k in range(arcs):
		var t0 := float(k) / float(arcs)
		var t1 := float(k + 1) / float(arcs)
		var th := fr + float(fl["theta_start_off"]) + (t0 + t1) * 0.5 * float(fl["turns"]) * TAU
		var y_hi := lerpf(float(fl["y_start"]), float(fl["y_end"]), t0) * h   # floor datum, descending
		var y_lo := lerpf(float(fl["y_start"]), float(fl["y_end"]), t1) * h
		# layer 1: the trough rides PROUD of the wall (it bridges over the on-skin dome ribs)
		reservations.append({"id": "flume_arc_%d" % k, "type": "decoration", "cyl": true, "layer": 1,
			"theta": wrapf(th, -PI, PI), "half_arc": TAU / 16.0,
			"y0": y_lo - 0.015 * h, "y1": y_hi + band_up, "keeps_clear": []})

# a wheel row [theta_off, y_center, dia] as a Vector3 for terse reads
static func w_row(row_v: Variant) -> Vector3:
	var row := row_v as Array
	return Vector3(float(row[0]), float(row[1]), float(row[2]))

## SOCKETS — the architecture->puzzle contract (director, 2026-07-09), now placed FROM the survey:
##   weak_point   structural weaknesses ON the silhouette profile — may crumble when hit
##   road         one per entrance threshold, facing out (main flagged for the level's spine)
##   bridge       where level bridges/walkable lanes dock (ledge rims, roof edges, hypelines arms)
##   balcony      content points on tier ledges (flora, lures, rest spots, set-piece controls)
##   door         the placed entrances themselves (the placement authority's record)
func _survey_sockets(placements: Array) -> void:
	sockets.clear()
	var comp := str(spec.get("composite", ""))
	var kb := float(str(kind).hash() % 1000)
	for pl_v in placements:
		var pl := pl_v as Dictionary
		var fr := pl["frame"] as Dictionary
		sockets.append({"kind": "door", "pos": fr["anchor"], "n": fr["n"], "main": bool(pl["main"])})
		sockets.append({"kind": "road", "pos": fr["anchor"], "dir": fr["n"], "width": 1.2, "main": bool(pl["main"])})
	if comp == "bulwark_towers":
		# the barrier WINGS: one reach socket off each flank (tips run legally past the envelope)
		var wgs: Dictionary = table_for(spec, "bulwark")["wing"]
		var bsz: Vector3 = spec.get("size", Vector3(4.6, 5.2, 3.4))
		for sxw in [1.0, -1.0]:
			sockets.append({"kind": "barrier_wing", "reach": true,
				"pos": Vector3(float(sxw) * bsz.x * 0.5, float(wgs["panel_h"]) * bsz.y * 0.5,
					float(wgs["lateral"]) * bsz.y),
				"dir": Vector3(float(sxw), 0, 0),
				"length": float(wgs["bay_len"]) * bsz.y * float(int(wgs["bays"]))})
	if str(spec.get("kind", "")) == "honeycomb_cooperative":
		var hc := table_for(spec, "honeycomb")
		var hsz: Vector3 = spec.get("size", Vector3(4.5, 10.0, 6.3))
		for row_v in ((hc["catwalks"] as Dictionary)["rows"] as Array):
			sockets.append({"kind": "balcony", "pos": Vector3(hsz.x * 0.5 + float((hc["catwalks"] as Dictionary)["out"]) * hsz.y * 0.5, float(row_v) * hsz.y + 0.05, 0.0),
				"n": Vector3(1, 0, 0), "radius": 0.5})
		sockets.append({"kind": "weak_point",
			"pos": Vector3(hsz.x * 0.5, (float((hc["hole"] as Dictionary)["y0"]) + float((hc["hole"] as Dictionary)["y1"])) * 0.5 * hsz.y, float((hc["hole"] as Dictionary)["z"]) * hsz.y),
			"n": Vector3(1, 0, 0), "radius": 0.9})
	if comp == "zone3_split":
		# the gutted wing: a balcony slot on every torn gallery, the weak point at the torn seam
		var z3 := table_for(spec, "zone3")
		var zsz: Vector3 = spec.get("size", Vector3(4.0, 5.4, 3.6))
		var zh := zsz.y
		var wing_cx := (float(z3["main_x1"]) + float(z3["wing_x1"])) * 0.5 * zh
		for sy_v in (z3["slabs"] as Array):
			sockets.append({"kind": "balcony", "pos": Vector3(wing_cx, (float(sy_v) + float(z3["slab_t"])) * zh, zsz.z * 0.5 - 0.3),
				"n": Vector3(0, 0, 1), "radius": 0.5})
		sockets.append({"kind": "weak_point", "pos": Vector3(float(z3["main_x1"]) * zh, 0.45 * zh, zsz.z * 0.5),
			"n": Vector3(0, 0, 1), "radius": 0.8})
		sockets.append({"kind": "bridge", "pos": Vector3((float(z3["main_x0"]) + float(z3["main_x1"])) * 0.5 * zh, zh, 0),
			"dir": Vector3(0, 0, 1), "width": 1.0})
	if comp == "open_files_awnings":
		# weak points on hash-picked skirt bands (the visible stepped facades); bridge sockets at
		# the flat core-roof edges. The sloped awning roofs hold no balcony slots.
		var lay: Dictionary = BaseShapeBuilder._awning_layout(spec)
		for k3 in range(2):
			var fi := int(BaseShapeBuilder._h01(kb + 3.0 + float(k3) * 13.7) * 3.99)
			var lv: Array = (lay["faces"] as Array)[fi]
			var li := int(BaseShapeBuilder._h01(kb + 8.0 + float(k3) * 5.1) * float(lv.size() - 1) * 0.99)
			var pts := lv[li] as Dictionary
			var mid: Vector3 = ((pts["E"] as Vector3) + (pts["F"] as Vector3)) * 0.5
			var wy := (mid.y + float(pts["bottom_y"])) * 0.5
			sockets.append({"kind": "weak_point", "pos": Vector3(mid.x, wy, mid.z), "n": pts["n"], "radius": 0.7})
		var core: Vector2 = lay["core"]
		var hh: float = lay["h"]
		for fd0 in [[Vector3(0, hh, core.y), Vector3(0, 0, 1)], [Vector3(0, hh, -core.y), Vector3(0, 0, -1)],
				[Vector3(core.x, hh, 0), Vector3(1, 0, 0)], [Vector3(-core.x, hh, 0), Vector3(-1, 0, 0)]]:
			sockets.append({"kind": "bridge", "pos": (fd0 as Array)[0], "dir": (fd0 as Array)[1], "width": 1.0})
		return
	if comp == "hypelines_mound":
		# every arm tip is a bridge dock; the LANE pair additionally carries its walkable deck
		# descriptor (flat at the level-1 datum) so the level layer can register grid cells +
		# an inter-level link without re-deriving the geometry (the walkable-lanes directive)
		var deck: Dictionary = table_for(spec, "hypelines")["deck"]
		for a in hypelines_arm_table(spec):
			var ad := a as Dictionary
			# "reach": an arm-tip dock legitimately extends past the massing envelope
			var sock := {"kind": "bridge", "lane": bool(ad["lane"]), "reach": true,
				"pos": ad["walk_tip"] if bool(ad["lane"]) else ad["tip"],
				"dir": (ad["dir"] as Vector3).normalized(), "width": float(deck["deck_w"])}
			if bool(ad["lane"]):
				sock["deck"] = {"start": ad["walk_base"], "end": ad["walk_tip"],
					"width": float(deck["deck_w"]), "walk_y": float(deck["walk_y"])}
			sockets.append(sock)
	if comp == "plumbing_lobed":
		# the flume's two mouths are walkable-lane sockets (the trough is a traversable deck)
		var fl: Dictionary = table_for(spec, "plumbing")["flume"]
		var hh2 := _height_total()
		for endp in [[0.0, float(fl["y_start"])], [1.0, float(fl["y_end"])]]:
			var tt := float((endp as Array)[0])
			var th := PI * 0.5 + float(fl["theta_start_off"]) + tt * float(fl["turns"]) * TAU
			var fy := float((endp as Array)[1]) * hh2
			var rc := radius_at(fy) + (float(fl["trough_w"]) * 0.5 - float(fl["wall_sink"])) * hh2
			sockets.append({"kind": "bridge", "lane": true,
				"pos": Vector3(cos(th), 0.0, sin(th)) * rc + Vector3(0, fy, 0),
				"dir": Vector3(cos(th), 0.0, sin(th)), "width": float(fl["trough_w"]) * hh2})
	if str(plan.get("kind", "")) == "drum":
		var hgt := float(spec.get("height", 5.0))
		var nw := 2 + int(BaseShapeBuilder._h01(kb + 1.0) * 1.9)
		for k in range(nw):
			var th := TAU * BaseShapeBuilder._h01(kb + 10.0 + float(k) * 7.7)
			var wy := hgt * (0.45 + 0.4 * BaseShapeBuilder._h01(kb + 20.0 + float(k) * 3.3))
			var nrm := Vector3(cos(th), 0.0, sin(th))
			sockets.append({"kind": "weak_point", "pos": nrm * radius_at(wy) + Vector3(0, wy, 0),
				"n": nrm, "radius": 0.7})
	else:
		var s: Vector3 = spec.get("size", Vector3(4, 6, 4))
		# cornice-corner weaknesses (two hash-picked corners) + one upper mid-face, ON the profile
		# extents at their height (a tiered box's upper corners sit on the shrunken tier)
		var c0 := int(BaseShapeBuilder._h01(kb + 2.0) * 3.99)
		for k2 in range(2):
			var corner := (c0 + k2 * 2) % 4
			var he := half_extents_at(s.y * 0.85)
			var cx := he.x if corner % 2 == 0 else -he.x
			var cz := he.y if corner < 2 else -he.y
			sockets.append({"kind": "weak_point", "pos": Vector3(cx, s.y * 0.85, cz),
				"n": Vector3(cx, 0, cz).normalized(), "radius": 0.7})
		sockets.append({"kind": "weak_point", "pos": Vector3(0, s.y * 0.7, half_extents_at(s.y * 0.7).y),
			"n": Vector3(0, 0, 1), "radius": 0.8})
		# roof-rim bridge connectors (flat boxes without tiers get their sockets at the parapet)
		if maxi(1, int(spec.get("tiers", 1))) <= 1:
			var hx := s.x * 0.5
			var hz := s.z * 0.5
			for fd in [[Vector3(0, s.y, hz), Vector3(0, 0, 1)], [Vector3(0, s.y, -hz), Vector3(0, 0, -1)],
					[Vector3(hx, s.y, 0), Vector3(1, 0, 0)], [Vector3(-hx, s.y, 0), Vector3(-1, 0, 0)]]:
				sockets.append({"kind": "bridge", "pos": (fd as Array)[0], "dir": (fd as Array)[1], "width": 1.0})
	# tier ledges (cyl or box): BRIDGE sockets at the rim quarters, BALCONY slots around the ring
	for lg in BaseShapeBuilder.tier_ledges(spec):
		var ld := lg as Dictionary
		var ly := float(ld["y"])
		for q in range(4):
			var smp: Dictionary = LedgeBuilder._ledge_center_sample(ld, (float(q) + 0.5) / 4.0)
			var opos := smp["pos"] as Vector3
			sockets.append({"kind": "bridge",
				"pos": Vector3(opos.x, ly, opos.z) + (smp["outward"] as Vector3) * 0.3,
				"dir": smp["outward"], "width": 1.0})
		var ns := 3 + int(BaseShapeBuilder._h01(kb + 40.0) * 2.9)
		for sl in range(ns):
			var smp2: Dictionary = LedgeBuilder._ledge_center_sample(ld, (float(sl) + 0.25) / float(ns))
			var bpos := smp2["pos"] as Vector3
			sockets.append({"kind": "balcony", "pos": Vector3(bpos.x, ly, bpos.z),
				"out": smp2["outward"], "size": 0.5})


# ============================================================================================
# READ SURFACE — what consumers query
# ============================================================================================

## Silhouette radius at height y (drums). Boxes answer their larger half extent so a radial consumer
## (pipe drapes) still gets a usable envelope.
func radius_at(y: float) -> float:
	if profile.is_empty():
		return float(spec.get("radius", 2.0))
	var first := profile[0] as Dictionary
	if y <= float(first["y"]):
		return _point_r(first)
	for i in range(profile.size() - 1):
		var b := profile[i + 1] as Dictionary
		if y <= float(b["y"]):
			var a := profile[i] as Dictionary
			var dy := float(b["y"]) - float(a["y"])
			if dy <= 0.0001:
				continue   # a step discontinuity: the segment above owns this y
			return lerpf(_point_r(a), _point_r(b), (y - float(a["y"])) / dy)
	return _point_r(profile[profile.size() - 1] as Dictionary)

## Half extents (hx, hz) at height y (boxes). Drums answer (r, r).
func half_extents_at(y: float) -> Vector2:
	if profile.is_empty():
		var r := float(spec.get("radius", 2.0))
		return Vector2(r, r)
	var first := profile[0] as Dictionary
	if y <= float(first["y"]):
		return _point_he(first)
	for i in range(profile.size() - 1):
		var b := profile[i + 1] as Dictionary
		if y <= float(b["y"]):
			var a := profile[i] as Dictionary
			var dy := float(b["y"]) - float(a["y"])
			if dy <= 0.0001:
				continue
			return _point_he(a).lerp(_point_he(b), (y - float(a["y"])) / dy)
	return _point_he(profile[profile.size() - 1] as Dictionary)

func _point_r(p: Dictionary) -> float:
	if p.has("r"):
		return float(p["r"])
	return maxf(float(p.get("hx", 2.0)), float(p.get("hz", 2.0)))

func _point_he(p: Dictionary) -> Vector2:
	if p.has("r"):
		return Vector2(float(p["r"]), float(p["r"]))
	return Vector2(float(p.get("hx", 2.0)), float(p.get("hz", 2.0)))

## The opening reservations (the door regions), in the legacy reserved-region shape the base mesh
## cutters and lattice builders consume.
func openings() -> Array:
	var out: Array = []
	for r_v in reservations:
		if str((r_v as Dictionary).get("type", "")) == "opening":
			out.append(r_v)
	return out

## The gameplay anchors in the legacy {weak_points, connectors, balcony_slots} shape
## (ex BaseShapeBuilder.gameplay_anchors — building_filler and the showcase read this).
func anchors() -> Dictionary:
	var weak: Array = []
	var conns: Array = []
	var balc: Array = []
	for s_v in sockets:
		var s := s_v as Dictionary
		match str(s["kind"]):
			"weak_point":
				weak.append({"pos": s["pos"], "n": s["n"], "radius": float(s["radius"])})
			"road":
				conns.append({"kind": "road", "pos": s["pos"], "dir": s["dir"],
					"width": float(s["width"]), "main": bool(s.get("main", false))})
			"bridge":
				var c := {"kind": "bridge", "pos": s["pos"], "dir": s["dir"], "width": float(s["width"])}
				if bool(s.get("lane", false)):
					c["lane"] = true
				if s.has("deck"):
					c["deck"] = s["deck"]   # the walkable-lane descriptor the level layer docks
				conns.append(c)
			"balcony":
				balc.append({"pos": s["pos"], "out": s["out"], "size": float(s["size"])})
	return {"weak_points": weak, "connectors": conns, "balcony_slots": balc}

## The whole measured drawing as one dictionary (deterministic printing / comparison).
func summary() -> Dictionary:
	return {"kind": kind, "datums": datums, "plan": plan, "profile": profile,
		"reservations": reservations, "sockets": sockets}


# ============================================================================================
# PLUMBING READ SURFACE — the construction passes build FROM these (never their own numbers)
# ============================================================================================

## The plumbing lathe rings in ABSOLUTE metres: [{y, r, lobes, amp, phase}]. The phase locks a lobe
## VALLEY onto the front axis, so the door cuts a sheltered valley wall (the plate's recessed entry).
static func plumbing_rings(spec_in: Dictionary) -> Array:
	var tbl := table_for(spec_in, "plumbing")
	var h := float(spec_in.get("height", 5.6))
	var lobes := int(tbl["lobes"])
	var phase := PI / float(lobes) - PI * 0.5
	var out: Array = []
	for row in (tbl["rings"] as Array):
		var r := row as Array
		out.append({"y": float(r[0]) * h, "r": float(r[1]) * h, "lobes": lobes,
			"amp": float(r[2]), "phase": phase})
	return out

## The hypelines lathe rings in ABSOLUTE metres (same shape as plumbing_rings; the valley-at-front
## phase puts the toll-gate door in a sheltered lobe groove).
static func hypelines_rings(spec_in: Dictionary) -> Array:
	var tbl := table_for(spec_in, "hypelines")
	var h := float(spec_in.get("height", 6.2))
	var lobes := int(tbl["lobes"])
	var phase := PI / float(lobes) - PI * 0.5
	var out: Array = []
	for row in (tbl["rings"] as Array):
		var r := row as Array
		out.append({"y": float(r[0]) * h, "r": float(r[1]) * h, "lobes": lobes,
			"amp": float(r[2]), "phase": phase})
	return out

## The ancourage lathe rings in ABSOLUTE metres — rows carry their own lobe count (the body is
## round, the dome rings are 2-lobed with rising amplitude: the cluster is ONE loft, no spheres).
static func ancourage_rings(spec_in: Dictionary) -> Array:
	var tbl := table_for(spec_in, "ancourage")
	var h := float(spec_in.get("height", 4.6))
	var phase := float(tbl["dome_phase"])
	var out: Array = []
	for row in (tbl["rings"] as Array):
		var r := row as Array
		out.append({"y": float(r[0]) * h, "r": float(r[1]) * h, "lobes": int(r[3]),
			"amp": float(r[2]), "phase": phase})
	return out

## The beacon lathe rings in ABSOLUTE metres (round — the bell-jar has no lobes).
static func beacon_rings(spec_in: Dictionary) -> Array:
	var tbl := table_for(spec_in, "beacon")
	var h := float(spec_in.get("height", 7.2))
	var out: Array = []
	for row in (tbl["rings"] as Array):
		var r := row as Array
		out.append({"y": float(r[0]) * h, "r": float(r[1]) * h, "lobes": 4, "amp": 0.0, "phase": 0.0})
	return out

## The LOCAL wall radius at (y, theta) on a survey lathe — ring-interpolated with the lobe
## modulation. The loft mesh and every mounted fixture consult THIS, so parts always touch the
## real skin (mereotopology).
static func lathe_local_r(rings: Array, y: float, theta: float) -> float:
	if y <= float((rings[0] as Dictionary)["y"]):
		return _ring_local_r(rings[0] as Dictionary, theta)
	for i in range(rings.size() - 1):
		var hi := rings[i + 1] as Dictionary
		if y <= float(hi["y"]):
			var lo := rings[i] as Dictionary
			var dy := float(hi["y"]) - float(lo["y"])
			if dy <= 0.0001:
				continue
			return lerpf(_ring_local_r(lo, theta), _ring_local_r(hi, theta), (y - float(lo["y"])) / dy)
	return _ring_local_r(rings[rings.size() - 1] as Dictionary, theta)

static func _ring_local_r(ring: Dictionary, theta: float) -> float:
	return float(ring["r"]) * (1.0 + float(ring["amp"]) * cos(float(ring["lobes"]) * (theta + float(ring["phase"]))))

## The flume helix sampled for construction: floor-datum centerline {theta, y, r} + section dims
## (metres). The centerline radius keeps the trough's inner rim sunk into the wall (support).
func flume_path(steps: int = 56) -> Dictionary:
	var tbl := table_for(spec, "plumbing")
	var h := _height_total()
	var fl: Dictionary = tbl["flume"]
	var rings := plumbing_rings(spec)
	var samples: Array = []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var th := PI * 0.5 + float(fl["theta_start_off"]) + t * float(fl["turns"]) * TAU
		var y := lerpf(float(fl["y_start"]), float(fl["y_end"]), t) * h
		var rc := lathe_local_r(rings, y, th) + (float(fl["trough_w"]) * 0.5 - float(fl["wall_sink"])) * h
		samples.append({"theta": th, "y": y, "r": rc})
	return {"samples": samples, "trough_w": float(fl["trough_w"]) * h, "depth": float(fl["depth"]) * h,
		"rail_h": float(fl["rail_h"]) * h, "water_w": float(fl["water_w"]) * h}

## The hypelines arm table in ABSOLUTE terms: per arm {az, base, dir, tip, pipe_r, len, lane,
## walk_base, walk_tip} — base/tip are the pipe CENTERLINE ends (base buried in the hub so the
## junction is solid); walk_base/walk_tip are the DECK surface ends (lane arms only meaningfully).
## The one source the massing details, the sockets, and the level-layer docking all read.
static func hypelines_arm_table(spec_in: Dictionary) -> Array:
	var tbl := table_for(spec_in, "hypelines")
	var h := float(spec_in.get("height", 6.2))
	var fr := PI * 0.5
	var deck: Dictionary = tbl["deck"]
	var out: Array = []
	for a_v in (tbl["arms"] as Array):
		var a := a_v as Dictionary
		var th := fr + float(a["az"])
		var radial := Vector3(cos(th), 0.0, sin(th))
		var dirv := (radial * cos(float(a["pitch"])) + Vector3.UP * sin(float(a["pitch"]))).normalized()
		var cy := float(a["attach"]) * h
		var base := radial * 1.1 + Vector3(0, cy, 0)   # buried in the hub — the junction reads solid
		var tip := base + dirv * (float(a["len"]) + 1.1)
		var walk_y := float(deck["walk_y"])
		var entry := {"az": float(a["az"]), "base": base, "dir": dirv, "tip": tip,
			"pipe_r": float(a["pipe_r"]), "len": float(a["len"]), "lane": bool(a["lane"])}
		if bool(a["lane"]):
			# deck ends: from the hub wall out to the tip, surface at the level-1 datum
			entry["walk_base"] = radial * 1.55 + Vector3(0, walk_y, 0)
			entry["walk_tip"] = Vector3(tip.x, walk_y, tip.z)
		out.append(entry)
	return out

## Absolute fixture frames for the detail passes — every position sampled off the surveyed skin.
func plumbing_frames() -> Dictionary:
	var tbl := table_for(spec, "plumbing")
	var h := _height_total()
	var rings := plumbing_rings(spec)
	var fr := PI * 0.5
	var out := {"slits": [], "wheels": [], "ribs": []}
	for s_v in (tbl["slits"] as Array):
		var s := s_v as Array
		var th := fr + float(s[0])
		(out["slits"] as Array).append({"theta": th, "y0": float(s[1]) * h, "y1": float(s[2]) * h,
			"w": float(s[3]) * h, "r0": lathe_local_r(rings, float(s[1]) * h, th),
			"r1": lathe_local_r(rings, float(s[2]) * h, th)})
	var wheel_rows: Array = (tbl["wheels"] as Array).duplicate()
	wheel_rows.append(tbl["stub_wheel"])
	for i in range(wheel_rows.size()):
		var w := w_row(wheel_rows[i])
		var th2 := fr + w.x
		(out["wheels"] as Array).append({"theta": th2, "y": w.y * h, "dia": w.z * h,
			"r": lathe_local_r(rings, w.y * h, th2), "stub": i == wheel_rows.size() - 1})
	var ribs: Dictionary = tbl["ribs"]
	for k in range(int(ribs["count"])):
		var th3 := fr + float(ribs["theta0_off"]) + TAU * float(k) / float(ribs["count"])
		(out["ribs"] as Array).append({"theta": th3, "y0": float(ribs["y0"]) * h,
			"y1": float(ribs["y1"]) * h, "r": float(ribs["r"]) * h})
	var sign: Dictionary = tbl["sign"]
	var sign_mid := (float(sign["y0"]) + float(sign["y1"])) * 0.5 * h
	out["sign"] = {"theta": fr + float(sign["theta_off"]), "y0": float(sign["y0"]) * h,
		"y1": float(sign["y1"]) * h, "w": float(sign["w"]),
		"r": lathe_local_r(rings, sign_mid, fr + float(sign["theta_off"]))}
	var hood: Dictionary = tbl["hood"]
	out["hood"] = {"theta": fr + float(hood["theta_off"]), "ridge": float(hood["ridge"]) * h,
		"eaves": float(hood["eaves"]) * h, "w": float(hood["w"]), "out": float(hood["out"]),
		"r": lathe_local_r(rings, 0.1, fr + float(hood["theta_off"]))}
	var casc: Dictionary = tbl["cascade"]
	var cth := fr + float(casc["theta_off"])
	out["cascade"] = {"theta": cth, "y_top": float(casc["y_top"]) * h, "w": float(casc["w"]),
		"r": lathe_local_r(rings, float(casc["y_top"]) * h * 0.5, cth)}
	var pipe: Dictionary = tbl["side_pipe"]
	var pth := fr + float(pipe["theta_off"])
	out["side_pipe"] = {"theta": pth, "y_top": float(pipe["y_top"]) * h,
		"dia": float(pipe["dia"]) * h, "valve_y": float(pipe["valve_y"]) * h}
	return out


# ============================================================================================
# DOOR PLACEMENT — the ONE authority (LatticeBuilder.entrances emits meshes from these)
# ============================================================================================

## Place the entrances for a base shape: the MAIN door at the front (+Z), plus a seeded number of
## SIDE doors distributed around the building (drum doors snap to tracery bays). Returns
## [{main, frame:{anchor,u,v,n}, w, h, region, bay}] — `region` is the reserved wall claim carrying
## BOTH extents (the opening the wall cuts, and the clearance the lattice keeps free).
static func door_placements(spec_in: Dictionary, params: Dictionary = {}) -> Array:
	var p := ENTRANCE_DEFAULTS.duplicate()
	var spec_ov: Dictionary = spec_in.get("entrances", {})
	for k in spec_ov.keys():
		p[k] = spec_ov[k]
	for k in params.keys():
		p[k] = params[k]
	var is_cyl := str(spec_in.get("shape", "box")) == "cylinder" or str(spec_in.get("door_frame", "")) == "cyl"
	# door_radius: the wall the door ACTUALLY cuts when it differs from the massing radius (the
	# plumbing drum sits inside its lobed skirt — the door lives on the drum, not the flare).
	var radius := float(spec_in.get("door_radius", spec_in.get("radius", 2.0)))
	var faces := _wall_faces(spec_in.get("size", Vector3(4, 6, 4)))
	var main_w := float(p["main_w"])
	var main_h := float(p["main_h"])
	var side_w := float(p["side_w"])
	var side_h := float(p["side_h"])
	var jamb := float(p["jamb"])
	var margin := float(p["reserve_margin"])
	var rng := SeededRng.new(int(str(spec_in.get("kind", "")).hash()) ^ 0x5177)
	var n_side := int(rng.call("randi_range", int(p["side_count_min"]), int(p["side_count_max"])))
	# On a TRACERY drum, doors live IN bays (the plate: each door framed by its bay's mullions) —
	# snap every door to a bay CENTRE and reserve exactly that bay.
	var snap_drum := is_cyl and str(spec_in.get("lattice", "")) == "tracery"
	var bays := int(spec_in.get("bays", DRUM_BAYS_FALLBACK))
	var dtheta := TAU / float(bays)
	var used_bays: Dictionary = {}
	var out: Array = []
	# box plans may survey their main door onto a chosen FACE at a lateral offset (the cleanstreets
	# toll portal rides the +X flank where the plate's road arrives, not the open queue front)
	var main_face := clampi(int(spec_in.get("door_face", 0)), 0, 3)
	var main_lat := float(spec_in.get("door_lateral", 0.0))
	var mf := _door_frame_cyl(radius, PI * 0.5) if is_cyl else _door_frame_face(faces[main_face], main_lat)
	var mrr := _reserve_region(is_cyl, radius, mf, main_w, main_h, jamb, margin, "door_main")
	if not is_cyl:
		mrr["x_center"] = main_lat
	if snap_drum:
		mrr["bay"] = 0
		used_bays[0] = true
	out.append({"main": true, "frame": mf, "w": main_w, "h": main_h, "region": mrr})
	for k in range(n_side):
		var sfr: Dictionary
		var side_bay := -1
		if is_cyl:
			var theta := PI * 0.5 + TAU * float(k + 1) / float(n_side + 1)
			if snap_drum:
				side_bay = wrapi(int(round((theta - PI * 0.5) / dtheta)), 0, bays)
				if used_bays.has(side_bay):
					continue   # bay already holds a door — drop this side entrance
				used_bays[side_bay] = true
				theta = PI * 0.5 + float(side_bay) * dtheta
			sfr = _door_frame_cyl(radius, theta)
		else:
			sfr = _door_frame_face(faces[1 + (k % 3)], 0.0)
		var srr := _reserve_region(is_cyl, radius, sfr, side_w, side_h, jamb, margin, "door_side_%d" % k)
		if side_bay >= 0:
			srr["bay"] = side_bay
		out.append({"main": false, "frame": sfr, "w": side_w, "h": side_h, "region": srr})
	return out

# The four vertical wall faces of a box plan (base at y=0): centre, in-plane U, outward normal, w, h.
static func _wall_faces(size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var my := size.y * 0.5
	return [
		{"c": Vector3(0, my, hz), "u": Vector3(1, 0, 0), "n": Vector3(0, 0, 1), "w": size.x, "h": size.y},
		{"c": Vector3(0, my, -hz), "u": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "w": size.x, "h": size.y},
		{"c": Vector3(hx, my, 0), "u": Vector3(0, 0, -1), "n": Vector3(1, 0, 0), "w": size.z, "h": size.y},
		{"c": Vector3(-hx, my, 0), "u": Vector3(0, 0, 1), "n": Vector3(-1, 0, 0), "w": size.z, "h": size.y},
	]

# A right-handed door frame (u x v = n) on the ground at the drum wall, at absolute angle `theta`.
static func _door_frame_cyl(radius: float, theta: float) -> Dictionary:
	var n := Vector3(cos(theta), 0.0, sin(theta))
	var v := Vector3(0, 1, 0)
	return {"anchor": n * radius, "u": v.cross(n).normalized(), "v": v, "n": n}

# A right-handed door frame on a box wall face (from _wall_faces) at lateral offset `lateral`.
static func _door_frame_face(face: Dictionary, lateral: float) -> Dictionary:
	var c: Vector3 = face["c"]
	var uf: Vector3 = face["u"]
	var n: Vector3 = face["n"]
	var v := Vector3(0, 1, 0)
	return {"anchor": Vector3(c.x, 0.0, c.z) + uf * lateral, "u": v.cross(n).normalized(), "v": v, "n": n}

# A door region carries TWO extents: the OPENING (open_*, = the actual door size — the base mesh cuts
# EXACTLY this so the frame sits on solid wall at the rim, not floating in an oversized hole) and the
# CLEARANCE (half_*/y_top, = door + frame + margin — what the lattice keeps clear).
static func _reserve_region(is_cyl: bool, radius: float, frame: Dictionary, door_w: float,
		door_h: float, jamb: float, margin: float, id: String) -> Dictionary:
	var n: Vector3 = frame["n"]
	var clear := door_w * 0.5 + jamb + margin
	var clear_y := door_h + jamb + margin
	if is_cyl:
		return {"id": id, "type": "opening", "cyl": true, "theta": atan2(n.z, n.x),
			"open_half_arc": (door_w * 0.5) / radius, "open_y_top": door_h,
			"half_arc": clear / radius, "y_top": clear_y, "y0": 0.0, "y1": clear_y}
	return {"id": id, "type": "opening", "cyl": false, "n": n, "x_center": 0.0,
		"open_half_w": door_w * 0.5, "open_y_top": door_h,
		"half_w": clear, "y_top": clear_y, "y0": 0.0, "y1": clear_y}

static func _n_name(n: Vector3) -> String:
	if absf(n.z) > 0.5:
		return "front" if n.z > 0.0 else "back"
	return "right" if n.x > 0.0 else "left"


# ============================================================================================
# VALIDATE — every silent failure mode becomes a loud string (empty result = a clean survey)
# ============================================================================================

func validate() -> Array[String]:
	var problems: Array[String] = []
	_validate_datums(problems)
	_validate_profile(problems)
	for r_v in reservations:
		_validate_reservation(r_v as Dictionary, problems)
	_validate_overlaps(problems)
	for s_v in sockets:
		_validate_socket(s_v as Dictionary, problems)
	return problems

func _validate_datums(problems: Array[String]) -> void:
	var plinth := float(datums["plinth"])
	var eave := float(datums["eave"])
	var crown := float(datums["crown"])
	if absf(crown - _height_total()) > 0.1:
		problems.append("%s: crown datum %.2f != massing height %.2f — the survey no longer traces the envelope" % [kind, crown, _height_total()])
	if plinth < -EPS or eave <= plinth or eave > crown + EPS:
		problems.append("%s: datum ladder broken (plinth %.2f <= eave %.2f <= crown %.2f must hold)" % [kind, plinth, eave, crown])
	var prev := plinth
	for s_v in (datums["storeys"] as Array):
		var s := float(s_v)
		if s <= prev + EPS:
			problems.append("%s: storey datum %.2f does not ascend past %.2f" % [kind, s, prev])
		if s > eave + 0.05:
			problems.append("%s: storey datum %.2f rises past the eave %.2f" % [kind, s, eave])
		prev = s

func _validate_profile(problems: Array[String]) -> void:
	var crown := float(datums["crown"])
	if profile.size() < 2:
		problems.append("%s: silhouette profile has %d control points — survey the silhouette before construction" % [kind, profile.size()])
		return
	var prev_y := -INF
	for p_v in profile:
		var p := p_v as Dictionary
		var y := float(p["y"])
		if y < prev_y - 0.0001:
			problems.append("%s: profile control point at y=%.2f breaks ascending order" % [kind, y])
		prev_y = y
		if _point_r(p) <= 0.0:
			problems.append("%s: profile radius/extent at y=%.2f is not positive" % [kind, y])
	if float((profile[0] as Dictionary)["y"]) > EPS:
		problems.append("%s: profile does not start at the ground (first y=%.2f)" % [kind, float((profile[0] as Dictionary)["y"])])
	if float((profile[profile.size() - 1] as Dictionary)["y"]) < crown - 0.05:
		problems.append("%s: profile stops at y=%.2f, below the crown %.2f" % [kind, float((profile[profile.size() - 1] as Dictionary)["y"]), crown])

func _validate_reservation(r: Dictionary, problems: Array[String]) -> void:
	var id := str(r.get("id", "?"))
	var crown := float(datums["crown"])
	var y0 := float(r.get("y0", 0.0))
	var y1 := float(r.get("y1", 0.0))
	if y1 <= y0:
		problems.append("%s: reservation '%s' has an empty height band (%.2f..%.2f)" % [kind, id, y0, y1])
	if y0 < -EPS or y1 > crown + 0.5:
		problems.append("%s: reservation '%s' leaves the building (band %.2f..%.2f, crown %.2f)" % [kind, id, y0, y1, crown])
	var on_drum := str(plan.get("kind", "")) == "drum"
	if bool(r.get("cyl", false)) and not on_drum:
		problems.append("%s: reservation '%s' is a drum arc on a box plan" % [kind, id])
	if not bool(r.get("cyl", false)) and r.has("n") and on_drum:
		problems.append("%s: reservation '%s' is a box face claim on a drum plan" % [kind, id])
	if str(r.get("type", "")) == "opening":
		var open_top := float(r.get("open_y_top", y1))
		# the wall the opening cuts must EXIST across the whole opening: the silhouette may not fall
		# inside the door plane below the lintel (the melted-tier door bug this check exists for)
		if on_drum:
			var wall_r := float(plan.get("wall_radius", plan.get("radius", 2.0)))
			for t in range(5):
				var yy := lerpf(y0, open_top, float(t) / 4.0)
				if radius_at(yy) < wall_r - 0.05:
					problems.append("%s: opening '%s' rises past its wall — silhouette %.2f falls inside the door plane %.2f at y=%.2f (fold the door into the wall band)" % [kind, id, radius_at(yy), wall_r, yy])
					break
		elif str(spec.get("composite", "")) != "open_files_awnings" and r.has("n"):
			# (the awning stack is exempt: its layout enforces door_clear_y on the ground facade,
			# and the survey's straight-taper profile under-reads the stepped skirts near ground)
			var nrm := r["n"] as Vector3
			var face_hw := _face_half_width(nrm)
			if face_hw <= 0.0:
				problems.append("%s: opening '%s' faces %s but no plan wall face does" % [kind, id, str(nrm)])
			elif absf(float(r.get("x_center", 0.0))) + float(r.get("open_half_w", 0.5)) > face_hw + EPS:
				problems.append("%s: opening '%s' runs off its wall face (|%.2f|+%.2f > %.2f)" % [kind, id, float(r.get("x_center", 0.0)), float(r.get("open_half_w", 0.5)), face_hw])
			else:
				var plane_d := _wall_plane_dist(nrm)
				for t in range(5):
					var yy2 := lerpf(y0, open_top, float(t) / 4.0)
					var he := half_extents_at(yy2)
					var ext := he.y if absf(nrm.z) > 0.5 else he.x
					if ext < plane_d - 0.05:
						problems.append("%s: opening '%s' rises past its wall — the silhouette falls inside the door plane at y=%.2f (fold the door into the wall band)" % [kind, id, yy2])
						break

# distance from the plan centre to the wall plane the reservation's normal points through
func _wall_plane_dist(n: Vector3) -> float:
	var he: Vector2 = plan.get("half_extents", Vector2(2, 2))
	return he.y if absf(n.z) > 0.5 else he.x

# the half-width of the plan wall face the normal points through (0 = no such face)
func _face_half_width(n: Vector3) -> float:
	for f_v in (plan.get("faces", []) as Array):
		if ((f_v as Dictionary)["n"] as Vector3).dot(n) > 0.9:
			return float((f_v as Dictionary)["w"]) * 0.5
	return 0.0

func _validate_overlaps(problems: Array[String]) -> void:
	for i in range(reservations.size()):
		for j in range(i + 1, reservations.size()):
			var a := reservations[i] as Dictionary
			var b := reservations[j] as Dictionary
			if not _res_overlap(a, b):
				continue
			var ta := str(a.get("type", ""))
			var tb := str(b.get("type", ""))
			var ida := str(a.get("id", "?"))
			var idb := str(b.get("id", "?"))
			if ta == "opening" and tb == "opening":
				problems.append("%s: openings '%s' and '%s' claim the same wall — reconcile the plan grid before meshing" % [kind, ida, idb])
			elif ta == "opening" or tb == "opening":
				var field := b if ta == "opening" else a
				var open_id := ida if ta == "opening" else idb
				if not (field.get("keeps_clear", []) as Array).has(open_id):
					problems.append("%s: '%s' overlaps opening '%s' without keeping it clear — restructure the field around the reservation or fold the part into the base" % [kind, str(field.get("id", "?")), open_id])
			elif (a.get("keeps_clear", []) as Array).has(idb) or (b.get("keeps_clear", []) as Array).has(ida):
				pass   # a declared ensemble: one part is deliberately composed around the other
			else:
				problems.append("%s: '%s' and '%s' both claim the same wall band — reconcile at the survey" % [kind, ida, idb])

# Two reservations overlap when they share a wall AND their height bands AND lateral spans intersect.
# `layer` separates radial shells: 0 = parts ON the wall skin (openings, slits, boards), 1 = parts
# riding PROUD of it (the plumbing flume bridging over the dome ribs) — different layers never fight
# for the same skin, so cross-layer overlaps are legal by construction.
func _res_overlap(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("layer", 0)) != int(b.get("layer", 0)):
		return false
	if float(a.get("y0", 0.0)) >= float(b.get("y1", 0.0)) - EPS \
			or float(b.get("y0", 0.0)) >= float(a.get("y1", 0.0)) - EPS:
		return false
	var a_ring := bool(a.get("ring", false))
	var b_ring := bool(b.get("ring", false))
	if a_ring or b_ring:
		return true   # a full-perimeter band shares every wall at its height
	var a_cyl := bool(a.get("cyl", false))
	var b_cyl := bool(b.get("cyl", false))
	if a_cyl != b_cyl:
		return false   # different wall languages = different walls
	if a_cyl:
		var dth := absf(fposmod(float(a["theta"]) - float(b["theta"]) + PI, TAU) - PI)
		return dth < float(a["half_arc"]) + float(b["half_arc"]) - EPS
	if not (a.has("n") and b.has("n")):
		return false
	if (a["n"] as Vector3).dot(b["n"] as Vector3) < 0.9:
		return false
	return absf(float(a.get("x_center", 0.0)) - float(b.get("x_center", 0.0))) \
		< float(a.get("half_w", 0.0)) + float(b.get("half_w", 0.0)) - EPS

func _validate_socket(s: Dictionary, problems: Array[String]) -> void:
	var skind := str(s.get("kind", "?"))
	var pos: Vector3 = s.get("pos", Vector3.ZERO)
	var crown := float(datums["crown"])
	# a REACH dock (an arm/lane tip) legitimately extends past the massing envelope
	var reach := skind == "bridge" and (bool(s.get("lane", false)) or bool(s.get("reach", false)))
	if pos.y < -0.5 or (pos.y > crown + 1.0 and not reach):
		problems.append("%s: %s socket floats off the building (y=%.2f, crown %.2f)" % [kind, skind, pos.y, crown])
		return
	var horiz := Vector2(pos.x, pos.z)
	match skind:
		"weak_point":
			if str(spec.get("composite", "")) == "open_files_awnings":
				if horiz.length() > _footprint():
					problems.append("%s: weak point off the awning stack (%.2f out)" % [kind, horiz.length()])
			elif str(plan.get("kind", "")) == "drum":
				if absf(horiz.length() - radius_at(pos.y)) > 0.2:
					problems.append("%s: weak point floats off the silhouette (|xz|=%.2f, profile %.2f at y=%.2f)" % [kind, horiz.length(), radius_at(pos.y), pos.y])
			else:
				var he := half_extents_at(pos.y)
				var on_x := absf(absf(pos.x) - he.x) <= 0.25 and absf(pos.z) <= he.y + 0.25
				var on_z := absf(absf(pos.z) - he.y) <= 0.25 and absf(pos.x) <= he.x + 0.25
				if not (on_x or on_z):
					problems.append("%s: weak point floats off the wall planes (%.2f, %.2f vs %.2f x %.2f at y=%.2f)" % [kind, pos.x, pos.z, he.x, he.y, pos.y])
		"door", "road":
			if pos.y > 0.3:
				problems.append("%s: %s socket is not at the threshold (y=%.2f)" % [kind, skind, pos.y])
			if str(plan.get("kind", "")) == "drum":
				var wall_r := float(plan.get("wall_radius", plan.get("radius", 2.0)))
				if absf(horiz.length() - wall_r) > 0.3:
					problems.append("%s: %s socket off the door wall (|xz|=%.2f, wall %.2f)" % [kind, skind, horiz.length(), wall_r])
			else:
				var he2 := half_extents_at(0.5)
				var on_x2 := absf(absf(pos.x) - he2.x) <= 0.3 and absf(pos.z) <= he2.y + 0.3
				var on_z2 := absf(absf(pos.z) - he2.y) <= 0.3 and absf(pos.x) <= he2.x + 0.3
				if not (on_x2 or on_z2):
					problems.append("%s: %s socket floats off the wall planes" % [kind, skind])
		"bridge":
			if not reach and horiz.length() > _footprint() + 1.0:
				problems.append("%s: bridge socket floats %.2f out from a %.2f footprint" % [kind, horiz.length(), _footprint()])
		"balcony":
			var on_ledge := false
			if str(spec.get("kind", "")) == "honeycomb_cooperative":
				# the torn flank's balconies are the catwalk rows
				var hcl := table_for(spec, "honeycomb")
				for row_l in ((hcl["catwalks"] as Dictionary)["rows"] as Array):
					if absf(float(row_l) * _height_total() + 0.05 - pos.y) <= 0.1:
						on_ledge = true
			elif str(spec.get("composite", "")) == "zone3_split":
				# the eroded ruin's balconies are the torn wing's floor slabs, not tier ledges
				var z3l := table_for(spec, "zone3")
				for sy_l in (z3l["slabs"] as Array):
					if absf((float(sy_l) + float(z3l["slab_t"])) * _height_total() - pos.y) <= 0.1:
						on_ledge = true
			else:
				for lg in BaseShapeBuilder.tier_ledges(spec):
					if absf(float((lg as Dictionary)["y"]) - pos.y) <= 0.1:
						on_ledge = true
			if not on_ledge:
				problems.append("%s: balcony slot at y=%.2f sits on no ledge/slab datum" % [kind, pos.y])
