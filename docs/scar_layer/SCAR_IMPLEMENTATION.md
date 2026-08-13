# Hex scar layer — implementation

## Files

| File | What it is |
| --- | --- |
| `scar_decals.png` | Decal atlas, 576×256, transparent. Authored at 1× tile scale (hex tile = 222×256). |
| `scar_decals-2x.png` | Same atlas at 2×, for cameras that zoom past 1:1. |
| `scar_decals.svg` | Vector source of the atlas, if you need to re-export at another scale. |

## Atlas regions

Region rects are in 1× pixels; double them for the 2× sheet.

| Region | x, y, w, h | Blend | Use |
| --- | --- | --- | --- |
| `crater_core` | 0, 0, 96, 96 | alpha | The breach. One per breach, scale 0.6–1.2. |
| `crater_rim` | 96, 0, 112, 112 | alpha | Cooled discolouration ring. Under the core, ~1.15× its scale, free rotation. |
| `heat_rim` | 208, 0, 128, 128 | add | Fresh-hit glow. Additive layer above the scar. |
| `soot_blob` | 336, 0, 192, 192 | alpha | Bloom. Full alpha over the impact tile, ~0.5 alpha over each other tile. |
| `crack_segment` | 0, 192, 128, 24 | alpha | Tileable run. Both ends sit at mid-height, so segments chain nose to tail. |
| `crack_branch` | 136, 192, 64, 48 | alpha | Hairline fork off a run. |
| `weld_plate` | 208, 192, 64, 32 | alpha | Repair patch bolted over an old crack. Rotate to the crack angle. |
| `pock` | 280, 192, 32, 32 | alpha | Grazing hit. Rotate along the incoming vector. |
| `ember` | 320, 192, 16, 16 | add | Thrown spark, fresh hits only. |

## Layer order

Per module, bottom to top:

1. module sprite (the hex tile art)
2. **scar layer** ← this system
3. tile lighting pass (rim light, contact shadow, vertex nodes)

The scar layer is clipped to the union of the module's hexes so damage never bleeds into a neighbour. Cheapest way in Godot: render the scar into a `SubViewport` the size of the module's bounding box with a hex-union mask, and draw the resulting `ViewportTexture` as one sprite. Re-render only when the damage tier or heat changes; per-frame cost is then one sprite.

## Damage model — append-only tiers

Damage never grows or re-rolls. Generate the full feature list once from the module's seed, tag each feature with the tier it appears at, and draw every feature whose tier ≤ current tier. Tier 3 therefore contains tier 1 and 2 exactly where the player last saw them.

| Tier | Name | Adds |
| --- | --- | --- |
| 1 | scuffed | soot bloom, 4 scorch streaks, 2 pocks per tile |
| 2 | breached | crater (core + rim) at the impact point, one crack run to every other tile of the footprint, 3 more streaks, 1 more pock per tile |
| 3 | patched | weld plate + stitch marks on each run, hairline branches, 2 more pocks per tile |
| 4 | veteran | the patches split, a second smaller breach opens elsewhere in the footprint with its own run, 2 more streaks, 1 more pock per tile |

Because the whole list is generated at max tier and then filtered, the RNG draw order is identical at every tier — that is what keeps earlier features frozen in place.

## Seeding from game state

Seed = hash of a stable string: module instance id + hit count. Same module, same history, same scar, across saves and clients.

```gdscript
static func fnv1a(s: String) -> int:
    var h := 2166136261
    for c in s.to_utf8_buffer():
        h = (h ^ c) * 16777619 & 0xFFFFFFFF
    return h

var rng := RandomNumberGenerator.new()
rng.seed = fnv1a("%s#%d" % [module_id, hit_count])
```

## Placement

Footprint tiles are hex centres in module-local pixels. For a pointy-top 222×256 tile the neighbour offsets are `(±222, 0)` and `(±111, ±192)`.

1. Pick the impact tile from the footprint, then jitter the impact point up to ±35 x, ±40 y off its centre.
2. Impact angle comes from the upper-left (the hull's light direction): `-2.5 + rng.randf() * 0.5` radians. Streaks and pock rotation follow it.
3. Crater radius: `19 + 14 * severity` px at 1× tile scale (severity ~1.5 gives a ~40 px crater, i.e. `crater_core` at scale 1.0).
4. Crack runs: from the crater edge toward each other tile centre, jittered ±0.15 rad, length 0.75–1.15× the distance. Lay `crack_segment` end to end along that path with ±0.1 rad per link.
5. Weld plate at 55–75% along each run, rotated to the run angle; three stitch marks perpendicular, spaced 13 px, just beyond it.
6. Pocks: place within ~88 px of each tile centre, radius 5–17 px, squashed 1.5–2.8× along the impact vector.
7. Clip everything to the hex union.

## Heat pass

`heat` runs 1 → 0 over ~1.5 s after the hit, on its own additive layer above the scar, using the same crater transform:

- `heat_rim` alpha ∝ heat² (glow drops away fast)
- molten outline alpha ∝ heat (the rim is the last thing to cool)
- 8–12 `ember` sprites scattered 0.9–2.8× crater radius, alpha ∝ heat²

Nothing in the cold scar changes as heat falls, so the crater does not shift under the fade.

## Palette

Hull darks `#0a0d10` `#0d1115` `#141a21` `#1b222a`; plate `#3d4854` `#54636f` `#6f7b87`; heat `#5c4029` `#7d4d27` `#c2521c` `#ff8a2e` `#ffd9a0`; soot `#05080b`.
