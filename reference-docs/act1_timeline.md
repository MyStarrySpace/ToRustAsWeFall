# Act 1 timeline and location-name reconciliation

Single source of truth for Act 1 scene order, canonical location names, and the
old working names the dialogue sheets still carry. Built from three sources:
the sheet tab order in `act1.xlsx`, the opening-narration chain (each scene
states what it opens out of), and the GDD section 4.4 location register. Where
those disagreed, the resolution and its evidence are recorded so no future
cross-reference relies on a dead name or a stale order.

## How to read this

Each scene row lists the dialogue sheet, the canonical GDD 4.4 name with its
shelter range and vernacular nicknames, the old working name to retire, and the
adjacency evidence that fixes its position. The canonical names come from GDD
section 4.4 (lines 712 to 725); the working names are what the sheets and the
session-start Act table used before the rebrand pass.

## The one resolved conflict: Stacks sits before the Rings

The session-start Act table and the GDD 4.4 register both placed the data
terminal zone at shelters 6 to 7, after the residential zone at shelters 4 to 5.
The sheets build the opposite order, and the evidence backs the sheets, so the
data terminal zone (Stacks) now sits before the residential zone (Rings), and
the GDD shelter numbers for those two zones need to swap.

Two independent lines of evidence. The opening narration of the Stacks reads
that the drainage channels give way to something industrial, placing the Stacks
immediately downstream of the Channels rather than three zones later. And the
drink-machine thread runs as a continuous character spine across four scenes in
exactly this order: it begins in the simulation (Ron offers it as a
top-performer perk; Aster's reflex is that he always grabs a drink first),
becomes grief in the Stacks (the dead support team, "I was gonna use their drink
machine," "It's not about the drink machine, it's about what I expected"), pays
off as involuntary delight in the Rings ("That is absolutely a drink machine"),
and lands as intimacy in love-dimensionless ("you'll give me a drink from your
drink machine"). The Rings beat only reads as a payoff if the Stacks grief
precedes it, so the order is fixed.

This ordering also has prior support in the design history. An April 11 planning
pass had already landed on the same flow, placing the Channels at shelters 2 to 3,
the data terminal zone at shelters 4 to 5 as pre-Myke Aster content, and the
residential zone at shelters 6 to 7 with Endo departing there at the furthest
point from his wall. So the Stacks-before-Rings decision is consistent with where
the thinking had previously trended, not a fresh reversal.

GDD EDIT TO MAKE (not yet applied): in section 4.4, swap the shelter numbers so
the data terminal zone precedes the residential zone. Pending a decision on
whether the shelter numbers themselves move or only the zones' relative order.

## Scene order

The played sequence, with the two pre-sim scenes first, then the descent.

| # | Sheet | Canonical zone (GDD 4.4) | Shelters | Old working name | Adjacency evidence | Rows | Status |
|---|-------|--------------------------|----------|------------------|--------------------|------|--------|
| 1 | aster-sim | The simulation (Zone 1) | n/a | sim | Pre-descent; Aster's sim | 20 | built |
| 2 | peris-sim | The simulation (Zone 1) | n/a | sim | Pre-descent; Peris's sim | 39 | built, plant workshop parked |
| 3 | elevator | Section 3B | 1-2 | section 3b | Opens in the escape room; the descent proper | 47 | built |
| 4 | tag-day | Section 3B | 1-2 | section 3b | Within the tutorial corridor | 34 | unexamined |
| 5 | endos-junction | Section 3B | 1-2 | endo's junction | Meet Endo; first night; "something's still alive in here" | 48 | unexamined |
| 6 | channels | Plumbing Power Project | 2-3 | Perivascular Channels | "The corridor opens. Water runs along the floor" | 31 | built |
| 7 | stacks | The Open Files Initiative | (was 6-7, now 4-5) | Processing Stacks | "The drainage channels give way to something industrial" | 62 | built |
| 8 | residential-rings | Greenfields Collective | (was 4-5, now 6-7) | Residential Rings | "Opens into a maintained ring corridor. Lit. Populated." | 32 | built |
| 9 | lockout | sim boundary checkpoint | n/a (6 o'clock) | lockout | Sim-boundary checkpoint, after the Rings per world rules | 43 | built |
| 10 | mother-flure | (route to core facility side) | TBD | mother flure | "This corridor's our route around... through to the core facility side?" | 65 | built |
| 11 | dead-flure | (with mother-flure block) | TBD | dead flure | Peris near the water, testing the air | 22 | built |
| 12 | gnawer-dodge | (offshoot corridor) | TBD | endo-wall (renamed) | "The offshoot corridor, walking. Endo ahead." | 63 | built |
| 13 | marco-drag | (Scarpet corridor) | TBD | marco drag | "The corridor opens into a wider space. A patch of Scarpet" | 23 | unexamined |
| 14 | myke-stacks | The Hypelines | 8-9 | supply lines / Iron Heart | Myke joins; footsteps behind them | 38 | unexamined |
| 15 | ouroboros | approach to the Paranucleus | TBD | ouroboros | "The path to the Paranucleus coils around an old service loop" | 21 | unexamined |
| 16 | nustle | (shelter beat, later-game slot) | TBD | nustle | Quiet shelter scene | 20 | built |
| 17 | nustle-de | (German variant of 16) | TBD | nustle-de | Scene-level DE transcreation | 20 | built |
| 18 | love-dimensionless | (shelter rest beat) | TBD | love dimensionless | "Aster sits with his back against something" | 17 | built |

## Canonical location register (GDD section 4.4)

The full vernacular-named register, for reference when a dialogue line needs a
place name. Names carry the civilizational-rebrand theme; nicknames are what
residents say day to day.

| Shelters | Canonical name | Nicknames | What it is |
|----------|----------------|-----------|------------|
| 1-2 | Section 3B | none (institutional designator) | tutorial corridor, elevator, iron bridge, meet Endo, first night |
| 2-3 | Plumbing Power Project | the Plumbing, the Power | water infrastructure |
| 4-5 | Greenfields Collective | the Greenfields, the Collective, Builder's | residential, planned cooperative community |
| 6-7 | The Open Files Initiative | the Open Files, Open | data terminals |
| 8-9 | The Hypelines | the Lines, the Hype, Iron Heart | resource distribution; corporate rebrand of cooperative planning infrastructure |
| 10 | Ancourage | the Anchor, Bedrock | foundation layer, Inflammashunt DZ junction, Act 1/2 transition |
| 11-12 | The Honeycomb Cooperative | Honeycomb, the Comb | worker housing, worker-cooperative federation |
| 13-14 | The Cleanstreets Initiative | Cleanstreets, the Streets | transit corridors and plazas |
| 15-16 | Beacon Hill | Beacon, the Hill, the Stand | archive preservation; preservation as institutional capture |
| 17-18 | Bulwark Wharf | the Wharf, Bulwark | Zone 2/3 boundary, barrier maintenance, Act 2/3 transition |
| 19-20 | Welcombe Springs | Picturesque, the Picture, the Springs | failed wellness-restoration; abandoned spa community |
| 21-22 | Harmonia | Harmony | gamma entrainment infrastructure; planned wellness community |
| 23-24 | Sunset Acres | the Acres, Sunset | areas the civilization gave up on |
| 25-30+ | Root Archive | the Root | foundational archive, Plexa's archive, endgame |

## Name reconciliation: dead names the sheets still carry

The dialogue sheets and the session-start Act table use working names that the
GDD 4.4 rebrand replaced. None of these appear in dialogue text yet (the sheets
use them only as tab names and key prefixes), so retiring them is a tracking job
rather than a find-and-replace through spoken lines. If a line ever needs to
name one of these places, use the canonical name or a nickname, never the
working name.

| Working name (retire) | Canonical name (use) |
|-----------------------|----------------------|
| Perivascular Channels | Plumbing Power Project |
| Processing Stacks | The Open Files Initiative |
| Residential Rings | Greenfields Collective |
| Supply Lines | The Hypelines |
| Basal Galleries | Ancourage |
| Maintenance Warrens | The Honeycomb Cooperative |
| Transit Corridors / Plazas | The Cleanstreets Initiative |
| Archive Depths | Beacon Hill |
| Filtration Membranes | Bulwark Wharf |
| Iron Marshes | Welcombe Springs |
| Resonance Chambers | Harmonia |
| Dead Zones (as a zone name) | Sunset Acres |

Note: "Dead Zone" survives as a generic term for a danger-zone pocket and for
Zone 3's lifeless corridors; only its use as the name for shelters 23-24 is
retired in favor of Sunset Acres.

## Open placement questions

These scenes are built but not yet pinned to a shelter range, recorded here so
the gaps are visible rather than guessed. The mother-flure block (10, 11),
gnawer-dodge (12), and marco-drag (13) all sit somewhere between the Rings and
the Hypelines but their exact shelter assignments are open. The three shelter
beats (nustle, nustle-de, love-dimensionless) are later-game slots without fixed
positions. The ouroboros scene names the Paranucleus approach, which is deep
Zone 3, so it likely belongs much later than its current tab position.
