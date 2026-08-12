# Gnawer — seam contract (derived from the turnaround, 2026-08-12)

Produced by the proportion-contract method in `blender/skills/creature-pipeline/SKILL.md`.
A dedicated agent derived every seam from NAMED sheet features and then tried to break the
frame; it found 12 conflicts, several of them in my brief. `frame_ok = true` after correction.

**Frame** (Z up, +Y forward/head, X right, ground Z=0):

```
height 0.410 m   length(Y) 0.833 m   width(X) 0.55 at the feet
Y = 0.5124 - 0.833 * side_x_frac      (side-L, head at LEFT)
Z = 0.410 * (1 - y_frac)
X = 0.550 * (front_x_frac - 0.500)
REAL scale: front 587.3 px/m, side-L 555.8 px/m  (NOT the 753 px/m my brief asserted)
```

## Seams

| name | centre (m) | normal | r | seg |
|---|---|---|---|---|
| `neck` | 0.000, +0.300, 0.210 | 0.000, +0.961, -0.277 | 0.070 | 10 |
| `jaw_hinge` | 0.000, +0.346, 0.146 | 0.000, +0.775, -0.631 | 0.070 | 10 |
| `shoulder_ring_left` | -0.164, +0.200, 0.240 | -0.289, -0.320, -0.902 | 0.028 | 8 |
| `shoulder_ring_right` | +0.164, +0.200, 0.240 | +0.289, -0.320, -0.902 | 0.028 | 8 |
| `hip_ring_left` | -0.158, -0.205, 0.240 | -0.098, -0.425, -0.900 | 0.035 | 8 |
| `hip_ring_right` | +0.158, -0.205, 0.240 | +0.098, -0.425, -0.900 | 0.035 | 8 |
| `ankle_fore_left` | -0.220, +0.138, 0.065 | -0.289, -0.320, -0.902 | 0.024 | 8 |
| `ankle_fore_right` | +0.220, +0.138, 0.065 | +0.289, -0.320, -0.902 | 0.024 | 8 |
| `ankle_hind_left` | -0.176, -0.283, 0.075 | -0.098, -0.425, -0.900 | 0.029 | 8 |
| `ankle_hind_right` | +0.176, -0.283, 0.075 | +0.098, -0.425, -0.900 | 0.029 | 8 |
| `dorsal_ridge_front` | 0.000, +0.454, 0.236 | 0.000, +0.769, -0.639 | 0.085 | 8 |
| `dorsal_ridge_crest` | 0.000, +0.035, 0.410 | 0.000, +1.000, 0.000 | 0.084 | 8 |
| `dorsal_ridge_tail_tip` | 0.000, -0.310, 0.210 | 0.000, +0.857, +0.514 | 0.033 | 8 |
| `dorsal_ridge_hood_apex` | 0.000, +0.260, 0.394 | 0.000, +0.986, +0.168 | 0.075 | 8 |
| `dorsal_ridge_saddle` | 0.000, +0.215, 0.385 | 0.000, +1.000, 0.000 | 0.085 | 8 |

Each seam's `derived_from` (which view, which feature, and the sum test) is preserved in the
workflow journal at `subagents/workflows/wf_fcc764e9-66c/journal.jsonl`.

**The five `dorsal_ridge_*` entries are POLYLINE STATIONS, not weld rings** — see conflict 6.
Instantiating the crest station as a circle with the given tangent as its normal would put
geometry 0.084 m above the top of the target box.

## Conflicts found (the reason this stage exists)

1. FALSE NUMBER IN THE FRAME — 'front 753 px/m vs side-L 748-753 px/m is isotropic to under 1%'. Measured: front is 587.3 px/m (323 px / 0.550 m) and 587.8 px/m (241 px / 0.410 m); side-L is 555.8 px/m (463 / 0.833) and 556.1 px/m (228 / 0.410). Neither view is anywhere near 753 px/m — that is 28% off for the front and 35% off for side-L. The isotropy claim is true WITHIN each view (0.09% front, 0.05% side-L) but the two views are 5.6% apart from each other. 753 px/m is consistent with an abandoned height of ~0.32 m, i.e. it is a leftover from a previous frame. Nothing in the contract derives from it, so the frame still works — but nobody may use 753, and no pixel count may be carried between the front and side views at a common scale.
2. AMBIGUOUS DENOMINATOR, 5% GROUND-PLANE ERROR — 'H=241..253' (front), 'H=228..233' (side-L), 'H=245..252' (rear). These ranges mix the creature-only height with the ground-contact-shadow-inclusive height. The published aspects 1.34 / 2.03 / 1.21 reproduce ONLY on 241 / 228 / 245 and on no other value in those ranges. An agent who takes H=253 for the front y_frac denominator puts Z=0 at 0.021 m BELOW the feet and every part of the model floats by 5% of its height. This is the same class of error as the old 'hood ridge at Z 0.40 with a 0.305 target height', and it will be resolved differently by different agents unless pinned. The cause is that the cast shadow is DARKER than the background, so the obvious |lum - bg| threshold includes it; the fix is to threshold on lum ABOVE background.
3. REAR VIEW IS ANISOTROPIC AS SPECIFIED, BY 1.7%. The brief's rear width 0.504 m is 296 px at the FRONT view's scale (296 / 587.3), but Z from the rear view divides by the rear view's own height (245 px / 0.410 m = 597.6 px/m). Using the rear view's own scale for X would give 0.495 m, not 0.504. The discrepancy is 0.009 m at the widest point. Recommend keeping 0.504 for rear X as stated (it puts front and rear on a common X scale, which matters more) and accepting that rear Z is 1.7% finer than rear X — but it must be stated once, not resolved four times.
4. REQUESTED RADII 0.05-0.09 ARE IMPOSSIBLE ON THE LIMBS. Measured sections: fore shank 0.039 (X, front) x 0.056 (Y, side-L); hind shank 0.065 (X, rear) x 0.049 (Y, side-L); forelimb at the shoulder station 0.051 (X, front). Every limb ring therefore lands at r 0.024-0.035. Forcing r >= 0.05 would double to quadruple the shank thickness and would break the verified front band profile — the outer silhouette runs at Z 0.08-0.12 measure only 0.024-0.070 m wide, and a 0.10 m diameter ankle would fatten the mid-shank and flatten the triangle back toward the T-shape the rebuild is supposed to eliminate. The 0.05-0.09 band is correct for the neck, jaw and ridge stations only. I have reported measured radii; the band needs amending, not the measurements.
5. A THREE-POINT DORSAL RIDGE CANNOT REPRESENT THIS PROFILE. The side-L top silhouette has TWO maxima, not one: the hood apex (Y +0.260, Z 0.3938) and the crest (Y +0.035, Z 0.4100), with a real saddle between them (Y +0.215, Z 0.385). A straight leg from the ridge front to the crest passes 0.077 m below the hood apex — 19% of the animal's total height, and it deletes the exact feature ('a broad triangular carapace HOOD sweeps back over the head into dorsal plates') that distinguishes this animal. I have supplied two extra stations (dorsal_ridge_hood_apex, dorsal_ridge_saddle); the ridge needs FIVE points. Escalating rather than silently dropping them.
6. RIDGE STATIONS ARE NOT WELD RINGS AND MUST NOT BE BUILT AS CIRCLES. If the crest station's radius (0.084) were instantiated as a ring with the supplied tangent as its normal, the ring would span Z 0.326..0.494 and place geometry 0.084 m above the top of the target box. For the five ridge entries, `normal` is the ridge tangent pointing forward (+Y) and `radius` is the carapace half-width in X at that station — a lofting parameter. The ten body seams ARE weld rings and their radius means what it normally means.
7. SIDE-L GROUND LINE IS NOT LEVEL — 0.029 m (7% of height) of unexplained rise. In side-L the hind-foot contact sits at y=572 (y_frac 0.921) while the fore-foot contact sits at y=588 (y_frac 0.991), a 16 px difference, even though in a true profile both pairs are at the same depth on the same ground plane and should share an image row. Either the render's ground is tilted or side-L carries a small yaw with the hindquarters further from camera. Consequence: any Z read off side-L for a rear-of-body part is biased HIGH by up to 0.029 m at the tail, tapering to zero at the fore feet. The reported tail-tip Z of 0.210 carries this and could be as low as 0.181. RULE FOR EVERYONE: all four feet contact Z = 0.000 exactly; take hind-limb Z from the REAR view. I cannot resolve which of the two causes it is from the sheet, so it is escalated.
8. FRONT AND REAR DISAGREE ON THE STANCE BY 8.7% — the cross-view test the brief demanded. Front-view total foot span is 0.550 m (fore toes, X +/-0.275); rear-view total is 0.504 m (hind toes, X +/-0.252). Both are 'the animal's widest', measured from opposite ends, and they do not match. Within each view the FAR pair reads much narrower than the near pair (front: hind/fore outer edge ratio 0.694; rear: fore/hind 0.658), which is pure parallax; combining the two gives a near/far magnification m = 1.48 and a TRUE hind/fore stance ratio of 1.03 — the two stances are essentially equal and the 0.550/0.504 pair is a calibration artifact, not a taper. Supporting evidence that the per-view widths are otherwise right: the carapace half-width at Z 0.205 measures 0.208 in the front view AND 0.208 in the rear view under the brief's own per-view widths, and the two views agree within 2% at every height from Z 0.29 down to Z 0.04 EXCEPT Z 0.10-0.14, where they are looking at different limbs. So: keep the per-view widths for the body, but be aware the target box's '0.55 at the feet' is the FORE-toe span only; the hind toes measure 0.504 in their own view. Do not build a tapering stance out of this.
9. SIDE-R IS NOT A PROFILE AND IS LISTED AS IF IT WERE. Its aspect is 1.731 against side-L's 2.031; a second pure profile at any common scale must reproduce 2.03. Side-R is a yawed three-quarter view (roughly 15-30 degrees, and the far side of the body is visible in it). The sheet header presents all four boxes as 'established and cross-checked' without that caveat, which invites exactly the mistake the measurement-discipline note warns about. NO Y AND NO X MAY BE READ FROM SIDE-R. It is a legitimate cross-check on HEIGHT only (238 px against front 241 and rear 245).
10. THE ORIGIN Y=0 IS NOT AN ANATOMICAL LANDMARK. The mapping Y = 0.5124 - 0.833*side_x_frac puts Y=0 at side_x_frac 0.6151 — behind the crest, over the hindquarter. It is not mid-body (that is x_frac 0.500, Y +0.096), not the ground-contact centroid (Y -0.073), not the hip (Y -0.205) and not the shoulder (Y +0.200). It is a stated convention and nothing more. Anyone who assumes Y=0 is the body centre will build the animal 0.096 m out of position along its longest axis.
11. THE CHIN, NOT THE FEET, SETS Z=0 IN THE FRONT VIEW. The front view's lowest creature pixel is the pale mandible slab at y=587; the fore-foot contact is at y=585, two pixels higher. The magnitude is negligible (0.003 m) but the fact is not: the chin slab RESTS ON THE GROUND in this pose, and the sheet's own y_frac=1.0 row is the chin. A builder who assumes the feet define the ground will hang the jaw 0.003 m in the air; one who does not notice the chin is grounded at all will build a floating jaw. The affordance sheet corroborates the pose — the dust puff issues from the chin at ground level.
12. MINOR, NO CONSEQUENCE: my lit bboxes differ from the published ones by one pixel on two edges — front right edge 377 vs 378, rear right edge 1613 vs 1614 (rear W 296 vs 297). Both are within the anti-aliased rim. Noted only so a later agent does not treat a one-pixel difference as evidence of a different measurement method.
