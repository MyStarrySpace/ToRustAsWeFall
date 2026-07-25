# Portals — the one contract (look, function, lens)

Every portal in the game is the SAME thing. No scene invents its own teleport visual or
its own crossing rules again. Director-ratified 2026-07-25 (the curecumin-portal ruling:
"work out a consistent definition of what portals look like and do").

## The four classes (names are load-bearing — never conflate)

| Class | File | Role |
|---|---|---|
| `Portal` | `scripts/game/world/portal.gd` | DATA ONLY: a directed zone-graph edge (from_zone → to_zone). Never placed, never rendered. |
| `PortalPad` | `scripts/game/objects/portal_pad.gd` | THE physical, clickable pad a member steps onto. Owns transit, queueing, state. |
| `WarpPortal` | `scripts/game/world/warp_portal.gd` | One-shot cosmetic warp-in VFX (ring + column + sparks). Not a place. |
| `PortalLens` | `scripts/game/world/portal_lens.gd` | The APERTURE VIEW: a reusable component that renders the destination through the portal opening with true parallax. Cosmetic only. |

## What a portal looks like

A portal is TWO fixtures at each end, plus the lens:

- **The pad ring** — a flat ring on the ground (the PortalPad's own glow mesh + the
  authored ring bed). This is the click target and where the queue forms.
- **The arch** — an upright ring over the pad; its APERTURE is the portal opening.
- **The lens** — when the pair is LIVE, the aperture renders the DESTINATION through a
  `PortalLens` (mirrored-camera SubViewport, the Peris-room technique): walk around it
  and the view parallaxes like a hole in the world. A DORMANT portal's aperture is dark.
  The lens is the wayfinding: you SEE where it goes. No text, ever.

**Color semantics** — the portal scheme is RED / PURPLE / BLUE, nothing else (director
ruling 2026-07-25: no gold portals; gold stays the Curecumin ITEM's hue and may appear
on the sealed gate in the garden, never on portal fixtures). The pad glow, arch, lens
rim, queue ghosts, and light all agree:
- **Purple** `(0.55, 0.42, 0.98)` — local transit pair inside one level (the pressure
  bridge's In/Out pads).
- **Blue** `(0.30, 0.55, 1.00)` — route/story portals that lead TOWARD another district
  (the Curecumin portal to the Greenfields threshold).
- **Red** — RESERVED: locked, hostile, or pursuit-granted portals (none shipped yet;
  use it for nothing else so the warning stays legible).
- Crawl/pipe transits (CrawlTunnel mouths) are NOT portals and keep their own grammar.

## What a portal does (the behavioral contract — all already in PortalPad)

1. **Click-gated INSPECTION** — click → walk to the pad → step through on arrival.
   Never proximity-fired.
2. **Pairs, bidirectional, reusable** — two pads pointed at each other; step through and
   back. A pad without a live partner is DORMANT (dark aperture, refuses transit).
3. **One at a time** — the activator's whole selection queues through, each member
   teleporting then walking OFF to its own arrival slot (the portal rule shared with
   CrawlTunnel). Hover previews GHOSTS on those slots; `compute_group_arrivals` is the
   one function both read, so the preview cannot lie.
4. **Impartial + stateful** — stun refuses transit; pursuers can be granted
   `begin_external_transit`; every queue/hop lives in GameState world_state, so replay
   and save reproduce crossings exactly.
5. **Never a bypass** (P8/P16) — a portal-only POCKET (pressure room, the neck garden)
   is grid-separated from the deck by non-walkable rows; the fragment test proves the
   naive walk cannot reach it and the portal can.
6. **Warped scenes** — pads are authored FLAT and configured with `configure_data`
   (never `configure`) so the canonical destination survives the coord_map without
   double-conversion.

## The lens contract (PortalLens)

- A `SubViewport` renders the destination: SAME `World3D` as the scene for a
  same-level pair (the curecumin pocket), or `own_world_3d` for a true-elsewhere view
  (the Peris → Monos-room portal, whose far side isn't in this scene).
- Per frame (`@rendering_only`): the lens camera = `dest_xf * (src_xf.affine_inverse()
  * live_camera.global_transform)`, fov copied — the exact mirror math from
  `peris_sim_sequence._update_portal_view`.
- The aperture mesh (a disc filling the arch) wears `resources/portal_lens.gdshader`
  (SCREEN_UV sampling of the viewport texture).
- Costs a scene render: `UPDATE_ALWAYS` only while the lens is on screen; the component
  drops to `UPDATE_DISABLED` when its aperture leaves the frustum.
- Headless: no live camera → the component no-ops; data-layer tests never depend on it.

## The curecumin portal specifically

Blue pair: the pad on the start ledge (flat s 1.6, lane −6.2) ↔ **the neck garden** — a
portal-only pocket INSIDE the drum's broken-coil neck (flat s 40..45, lanes −9.9..−7.4,
the pressure-pocket grid pattern): green growth in the break, a sealed Greenfields
Collective gate, and the route READ moved onto that gate. The Curecumin itself is NOT
here (GDD §9.2/9.4 — the reward waits in a Greenfields home); the garden is the promise,
seen live through the lens from the very first ledge.
