# Weak-wall collapse slab

Portable, UV-mapped source for the reusable generated-landmark collapse presenter.

- `weak_wall_slab.obj`: bottom-pivoted slab in metres, Y up.
- `weak_wall_slab.mtl`: references the shared external Channels wall-panel texture.
- Runtime wrapper: `scenes/game/weak_wall_collapse_piece.tscn`.

The data-fragment loader instances several slabs and derives their fall transforms from the saved
weak-wall deadline. Collision and the analytic debris consequence remain gameplay-owned by the
loader; this model is presentation only and can be edited directly in Blockbench.
