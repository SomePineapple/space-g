# Art Style Guide — 2D Game Asset Set

Reference this before building or editing any hex tile, ship part, or station. Covers all four factions: Ancient, Corporate, Pirate, Spaceship(generic/neutral).

## Master geometry (do not change)
- Hex tile: flat-top hexagon, `viewBox 0 0 222 256`, points `111,0 222,64 222,192 111,256 0,192 0,64`.
- Multi-hex fused mounts: 2-hex `500x460`, 3-hex triangular `500x540/620`. Reuse existing polygon unions (see `Ancient Hex Tiles.dc.html`) rather than inventing new fusions.
- Corner beacon nodes sit at the 6 hex vertices; pulsing `animate opacity` 3s loop alternating phase.

## Faction palettes (oklch family — same chroma/lightness band per faction, hue is the only differentiator)

All factions share roughly: background ~L 0.15–0.2 (near-black, faction hue tint), midtone hull L 0.30–0.40, accent glow L 0.75–0.85 at moderate-high chroma, warm highlight (bolts/nodes) around amber/gold. Keep new colors inside these bands — don't introduce a new saturation/lightness island.

- **Ancient** (precursor/organic-tech): violet hull `#241b3e`→`#3a2f5c`, structural gold `#d9b25a`, energy teal `#6fe3d6`, hot core `#fff6dc`/`#f2dfa0`. Background `#0d0f1a`.
- **Corporate** (industrial fleet): slate hull `#2b3542`→`#4a5763`/`#333f4d`, hazard amber `#f2c14e`, accent cyan `#2a8fa3`→`#55d6e8`/`#8fe9f2`. Background `#0a0d12`.
- **Pirate** (scavenged): brown/rust hull `#332a22`→`#57493c`/`#463b31`/`#2c261f`, warning orange `#e07a2e`/`#7a2a0a`/`#ffb35c`, trim `#8a7461`/`#6b5a49`. Background `#332a22`.
- **Spaceship/neutral**: cool slate `#2b3542`/`#171d24`/`#5a6b7a`, cyan accent `#2a8fa3`/`#55d6e8`, warm node `#f2c14e`.

**Corporate accent fix (per design proposal):** keep `#f2c14e` amber (already in-band with other factions' warm highlight). Re-tune the cyan family (`#2a8fa3`/`#55d6e8`/`#8fe9f2`) so its lightness/chroma matches the Ancient teal's role (`#6fe3d6` is L≈0.83 C≈0.13 hue≈185; Corporate cyan should land in the same L/C band, just its own hue) — don't restyle the panels, only re-derive the accent hex values from the shared band next time they're touched.

## Ancient construction recipe — SEAMLESS, not per-tile

This is the main fix. Old approach (don't repeat): each tile draws its own `radialGradient` centered at its own local center, its own hull ellipse, and an identical gold diamond decal, then gets sealed with a hard `stroke="#100a1c"`. Result: visibly separate badges.

New approach for any new Ancient tile or station piece:
1. **One shared field.** Define a single large radial gradient (e.g. `g-ancient-field`, centered where the ship's core/heart actually is in world space) once per file, sized to cover the full station/tile-sheet extent. Every tile's background rect samples this same gradient via `gradientUnits="userSpaceOnUse"` and a per-tile `x/y` offset — never a fresh gradient re-centered per tile. This guarantees color continuity: two adjacent tiles sampling the same field at adjoining coordinates get matching color, no seam.
2. **No hard hex border.** Never stroke the outer hex polygon in near-black. Either omit the stroke entirely or stroke at ≤10% opacity in the field's own midtone — the shape should be implied by content, not fenced by an outline.
3. **Diamond/lattice is structural, not decorative.** Don't stamp the identical gold diamond outline on every tile. Instead run one continuous faint lattice path across the whole sheet (computed once, clipped per tile) so it reads as the ship's skeleton continuing behind each part, not a repeated logo.
4. **Cross-edge linework.** Any vein/arc/energy line that reaches a hex edge must terminate at a coordinate that matches where the neighboring tile's linework enters at that same shared edge (same edge-midpoint or vertex, same stroke width/color at the seam). Plan multi-tile compositions edge-first: decide the seam points before drawing tile interiors.
5. **Soft part transitions.** Favor overlapping soft ellipses with gradient falloff/blur where one mechanism meets another (e.g. reactor into hull) over crisp nested polygons with their own outline — nesting-with-outline is what currently makes each internal shape look like its own sticker.
6. **Station-scale parity.** Hero stations (e.g. Ancient Waypoint Sanctum) must use the same shared-field + no-hard-seam technique as the hex tiles, so zooming from station to tile-kit feels like the same material at different scales.

Quick self-check before shipping a new Ancient asset: cover the hex boundary with your hand — can you still tell a tile edge was there from a color jump or outline? If yes, it's not done.

## Corporate construction recipe — keep clunky, unify accent only

Keep: visible plating seams, rivets/hazard stripes, hard dark outlines (`#10141a`/`#171d24`), boxy nested polygons, exposed structural gantries/struts. This is correct and intentional — do not soften it.

Change only: derive the accent cyan from the shared oklch band described above rather than an arbitrary bright cyan, so it feels coordinated with Ancient teal / other factions' glows even though the panel language stays blocky. Amber `#f2c14e` already fits — keep using it for bolts/hazard/warm glow accents.

## Cross-faction checklist for any new asset
- [ ] Palette pulled from the faction's existing hex list above (no new arbitrary hues).
- [ ] Accent chroma/lightness matches the shared band, only hue changes per faction.
- [ ] Ancient: no hard hex-outline stroke; background gradient is the shared field, not tile-local; linework continues across seams; no repeated identical decal.
- [ ] Corporate/Pirate: seams, bolts, and hard outlines kept — these factions are meant to look constructed.
- [ ] Corner beacon nodes present and animated where the tile is part of the standard hex kit.
- [ ] `showGuides`/`showLabels` props preserved for kit files (View section toggles).
