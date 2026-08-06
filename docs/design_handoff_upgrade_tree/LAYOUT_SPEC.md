# Handoff: Upgrade Tree screen

Source design: `Ship Upgrades.dc.html`. This document describes the data model and the layout
algorithm so the screen can be rebuilt in engine without re-deriving either.

The design deliberately keeps **all tree content as data**. There is no per-category layout code —
one algorithm positions any tree that follows the schema below. Adding an upgrade is a data edit.

---

## 1. Data model

### Category

| Field | Type | Notes |
|---|---|---|
| `key` | string | Stable id, used for save data. |
| `label` | string | Sidebar text. |
| `hue` | number | OKLCH hue, 0–360. Default colour for every node in the tree. |

### Node

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Unique **within its category**. `root` is reserved. |
| `tier` | int | yes | Ring index. `0` = root (owned from the start). Controls radius only. |
| `parents` | string[] | yes | Ids in the same category. **All** must be unlocked. `[]` for root. |
| `label` | string | yes | Shown under the node and in the detail panel. |
| `glyph` | string | yes | 2–3 char fallback shown until an icon exists. |
| `desc` | string | yes | Detail panel body. |
| `cost` | string | yes | Detail panel cost line. Swap for a structured type in engine. |
| `icon` | string | no | **Icon slot.** Path/handle for the real art. When set it replaces the glyph; sized at 52% of the node diameter, centred. |
| `hue` | number | no | Starts a new coloured branch. Every descendant inherits it. |

### The two rules that matter

**Prerequisites are AND, never OR.** `parents` is the complete requirement list. A node with one
parent is a normal chain step; a node with two or more is a **merge** and needs *all* of them. This
is how Weapons gates `Unified Fire Control` behind both `Beam Focusing` (laser branch) and
`Guided Fins` (missile branch). No separate "merge" flag exists — arity carries the meaning.

```
isUnlocked(cat, id)  -> id === 'root' || save[cat].includes(id)
isAvailable(cat, n)  -> !isUnlocked(cat, n.id) && n.parents.every(p => isUnlocked(cat, p))
```

Those two predicates are the entire gameplay logic. Everything else is presentation.

**Colour marks the branch.** A node's hue resolves by walking up `parents[0]` until a node declares
`hue`, falling back to the category hue. A merge node inherits the hue of *every* branch feeding it
and renders as a two-tone circle — that is the visual cue that it needs more than one line of
research. This is computed, not authored.

---

## 2. Adding content

**Another upgrade in an existing chain** — append a node whose `parents` is the node it follows and
whose `tier` is one higher. Nothing else changes; the fan re-balances.

**A new branch** (e.g. a fourth weapon type) — add a tier-1 node with `parents: ['root']` and its own
`hue`. Its subtree picks up the colour automatically and the arc re-divides between branches.

**A new merge** — add a node listing two or more ids in `parents`. Give it a tier above its highest
parent. It is placed between its parents automatically.

**A whole new category** — add a `CATS` entry and a `TREES[key]` array with a tier-0 `root`.

Keep branches symmetric — if one branch of a pair gets an offshoot, give its mirror one too, or the
arc reads lopsided. The layout mirrors *ordering*, not *content*.

---

## 3. Layout algorithm

Polar. The tree is a fan centred below the viewport; `tier` maps to radius, angle is allocated by
recursive subdivision.

1. **Span allocation.** The root owns `[-MAX_ANGLE, +MAX_ANGLE]` (currently ±72°). Each node splits
   its span evenly among its children; a child's angle is its span's midpoint. Only **single-parent**
   nodes claim span — merges are excluded so they never steal room from a branch.
2. **Mirroring.** In the right-hand half (span midpoint > 0) the child order is reversed before
   allocation. Without this, "first child" means outermost on the left and innermost on the right and
   the tree comes out crooked.
3. **Merge placement.** After allocation, a merge node's angle is the mean of its parents' angles,
   and its radius is pushed out by `0.4 × STEP` so it sits on its own ring — otherwise it shares a
   radius with single-parent siblings a small angle away and their labels collide.
4. **Radius.** `BASE_R + tier × STEP` (+ the merge offset).

### Connectors

Each edge is a **polar elbow**: an arc along the parent's ring to the child's angle, then a straight
radial spoke outward. This is what gives the tree its structured look; straight diagonals read as a
scribble. Two segments, one SVG path:

```
M <parent>  A r r 0 0 <sweep> <parent radius, child angle>  L <child>
```

### Labels

Label placement is the one genuinely fiddly part, and it is not a styling detail — get it wrong and
labels sit on top of circles.

- Near the arc's centre, "down" points at the hub, so the label is offset **outward along the node's
  own radius** and anchored by its **bottom** edge (`translateY(-100%)`), so a wrapped second line
  grows away from the circle rather than onto it.
- Near the arc's ends the radius is near-horizontal, so a wide label box would reach into the next
  ring. There "down" is tangential and safe, so the label hangs below, anchored by its top edge.

The bounding box used for fit-to-panel scaling **must** reserve label height on whichever side each
label actually lands. Reserving only below clips every capstone, since capstones sit at angle 0 with
their label above them. Placement and reservation share one function for exactly this reason.

### Fitting

The frame is measured from the real extent of nodes *and* labels, then uniformly scaled to the panel.
Do not use a fixed canvas: a wide fan gives a ~2:1 box that a ~1.5:1 panel can never fill, so width
binds, the scale collapses and the tree shrinks no matter how much spacing you add.

---

## 4. State and persistence

- Unlocks: `{ [categoryKey]: string[] }` — ids only. Node definitions are content, not save data, so
  adding upgrades never invalidates a save.
- Last viewed category persists (`shipUpgrades:lastCategory`) and is restored on open; falls back to
  `power`.
- Detail panel follows hover, falling back to the last click, so it never flickers empty.
