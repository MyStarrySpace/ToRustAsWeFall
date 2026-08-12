# Flora and fauna affordance sheets — batch 01

Generated with the built-in image generator on 2026-08-11. These are visual
development references only. They do not change the implementation labels in
`ENEMY_GAMEPLAY_ROSTER_AUDIT.md`.

## Sheet grammar

Every sheet uses four wordless reads: a dominant three-quarter hero, a filled
black silhouette thumbnail, a gameplay-affordance state, and a hurt/death or
cooldown state. Shape carries identity first, state change carries function
second, and color/emission only reinforces the read. Geometry must remain
buildable from a small kit of large, UV-mapped low-poly forms.

Style references used for all four sheets:

- `reference-images/concept/fauna/sapscraps-feral-reclaimer-concept-01.png`
  for multi-view sheet discipline and faceted painterly finish.
- `blender/previews/ENT-016_tended.png` for the in-game Flure's restrained
  palette, low-poly economy, and diorama-on-dark presentation.

## Generated sheets

| Species | Canonical read protected | Output |
| --- | --- | --- |
| Meeb | Many food-cups; one dilates before suction; collapses to a puddle | `reference-images/concept/fauna/meeb-affordance-concept-01.png` |
| Spiker | Triangular soma, one apical mast, chunky irregular dendritic crown; persistent delayed LOS filament | `reference-images/concept/fauna/spiker-affordance-concept-03.png` |
| Seefern | Lantern made of glowing veins; one foliage card per complete frond | `reference-images/concept/flora/seefern-affordance-concept-03.png` |
| Hushbloom | Card-based compound leaves; folded cards and deflated pulvini mean cooldown | `reference-images/concept/flora/hushbloom-affordance-concept-02.png` |

## Final prompt set

All prompts used the `stylized-concept` image-generation use case, prohibited
text and UI, and named the two style references above as references only.

### Meeb

Design one canon Meeb as four separated wordless views: dominant three-quarter
idle hero, pure-black silhouette thumbnail, feeding wind-up, and death puddle.
Use one small-dog-sized translucent amoeboid individual in every view. Its
identity is several large deep food-cup concavities aimed in different
directions — many mouths, never a face. Show a central nucleus and a few simple
vacuole masses, plus one low broad pseudopod. In the wind-up, exactly one cup
turns toward the target, dilates, puckers outward, and glows enzyme-yellow. Use
large faceted pale green-grey masses with painterly membrane variation. Avoid
eyes, teeth, legs, machinery, mascot-slime styling, microscopic detail, and a
busy environment.

### Spiker

Design one canon Spiker as four separated wordless views: dominant idle hero,
pure-black silhouette thumbnail, target-lock wind-up, and damaged/dead state.
Build it from a dense triangular soma rooted to the floor, exactly one thick
vertical apical stalk, one sparse horizontal dendritic crown, and low basal
dendrites. Pale teal-white tissue carries dark continuous veining. In the
attack view, exactly one crown branch brightens and forms one continuous taut
filament toward an off-frame target; spaced pulses moving along it communicate
a delayed connection, not a projectile. The damage state has a cracked slumped
stalk and sheared crown branches. Avoid guns, muzzle flashes, instant bolts,
faces, flowers, foliage, towers, and machine parts.

Director revisions: the original fine dendritic crown disappeared at gameplay
distance and carried uneven visual weight. Revision `-02` proved the chunky-arm
language but became a radial star. The selected `-03` sheet keeps broad negative
gaps and thick primary arms while varying attachment height, length, angle,
bend, and fork placement. Compact mass on one side counterweights longer
sweeps on the other, so the anatomy is irregular but its visual center remains
over the stalk. The attack still originates from one arm and remains a
continuous delayed LOS connection.

### Seefern

Design one canon Seefern as four separated wordless views: dominant tended
hero, pure-black silhouette thumbnail, wild-to-tended comparison, and dying
state. Use five to seven strongly arcing fronds from a simple moss base. Each
frond has a bright cool-teal rachis and sparse paired rounded-diamond leaflets;
each leaflet has one dark oval botanical marking encircled by a bright vein
ring. It must read first as a small lantern made of glowing veins and second as
many outward-facing eye markings. Wild is dim and folded, tended opens wider
and lights from base to tip, and dying leaves one weak frond among dark wilted
ones. Keep the construction modular and avoid literal eyeballs, flowers,
mushrooms, hundreds of leaflets, and realistic foliage density.

The selected `-03` sheet records the production construction ruling: each
complete Seefern frond is one thin double-sided foliage card. The rachis,
leaflets, eye marks, emissive veins, fiddlehead curl, and negative gaps are
painted into that card's alpha-cut texture; they are not separate meshes.

### Hushbloom

Design one canon Hushbloom as four separated wordless views: dominant charged
hero, pure-black silhouette thumbnail, triggered folded state, and recharging
or damaged state. Use four to six low spreading compound leaves. Each is a
clear comb of eight to twelve paired polygon leaflets on a purple-green rachis,
with a conspicuous swollen translucent pulvinus at every attachment. Charged
means lifted stems, open combs, and swollen nodes. Triggered means the pairs
fold inward in sequence, the leaves droop into narrow fans, the nodes deflate,
and a brief lavender-grey haze hangs around the plant. Recharging stays folded
while nodes partially refill. Avoid flowers, mushroom caps, explosions,
lightning, faces, unreadably thin stems, and dense realistic foliage.

Director revision: Hushbloom foliage is card-based. Each compound leaf is one
thin double-sided alpha-cut card attached to a mesh stem/rachis. Paired
leaflets and their gaps are texture silhouettes, while the swollen pulvinus
nodes may remain small faceted meshes so charge state stays readable. Triggered
cards droop or rotate edge-on rather than articulating individual leaf meshes.

## Remaining concept-sheet queue

Existing developed fauna sheets cover Sapscraps, Ferrules, Hidras,
Naturalizers, and Redactors. Batch 02 adds Crusts, Candids, and Gnawers; the
remaining fauna gaps are Tanglers, Flares, and Toxos. Batch 02 also adds
Capbage; the remaining flora sheets are Scarpet, Gasafoetida, Climbvine,
Mother Flure, Forget-me-nots, and Resolution Roots.
Existing ENT cards remain the source reference for flora anatomy; new sheets
must clarify construction and states without silently redesigning canon.
