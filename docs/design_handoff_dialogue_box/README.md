# Handoff: Dialogue Box (bottom-of-screen comms panel)

## Overview
A bottom-anchored dialogue panel for conversations with NPCs — typewriter text, a speaker identity line, click/key to advance, and an optional list of numbered player replies on the final line of a node. An optional character bust stands behind the panel when the speaker has portrait art.

**Ship option 1C.** The prototype file also contains 1A (text-only bar with a notched speaker tab) and 1B (inset 132px portrait comms feed) for comparison — do not implement those. This document describes 1C only.

## About the design files
`Dialogue Box.dc.html` is a design reference authored in a bespoke HTML component format used by the design tool. It shows intended look and behaviour; it is not production code to copy. Recreate it in the game's existing HUD/UI layer using that layer's established patterns. All layout is plain CSS flexbox and absolute positioning, so it maps directly.

`game-screenshot-context.png` is the live game screenshot the panel is composed over — use it to check in-situ placement against the existing HUD (resource bars top-left, SYSTEMS panel, cargo chip bottom-left).

## Fidelity
**High-fidelity.** Colours, typography, geometry, and interaction behaviour are final-intent. Deliberately unfinished: the bust is a striped placeholder awaiting character art, dialogue copy is sample text, and no audio design exists.

---

## Layout (option 1C)

The whole thing is one bottom-anchored stack — bust and panel are **siblings in a vertical flex column**, not independently positioned. This matters: the panel's height changes when replies appear, and stacking is what keeps the bust's base hidden behind the panel in both states.

```
container (position:absolute; left:28px; right:28px; bottom:96px;
           display:flex; flex-direction:column; align-items:flex-start)
├── bust        (optional; margin-left:244px; margin-bottom:-42px; 210×230)
└── panel       (align-self:stretch)
```

- **Bottom offset 96px** (not flush to the screen edge) — this clears the existing cargo chip in the bottom-left HUD. Do not reduce it without relocating that widget.
- **Side inset 28px** left and right; the panel is full-width between those insets.
- **Bust overlap** is the `margin-bottom:-42px`, so 42px of the bust's base always sits behind the panel. The bust has `border-bottom:none` and `border-radius:6px 6px 0 0` — its open bottom edge must stay covered.
- **Bust horizontal position** `margin-left:244px`. It is deliberately not at the far left: at left:28px it collided with the SYSTEMS panel in the top-left HUD. If character art is wider than 210px, grow it rightward.

### Panel
- Fill `rgba(16,21,27,0.9)`, 1px border `rgba(85,214,232,0.22)`, `border-radius:6px`, `padding:18px 24px`.
- Whole panel is the click target (advance / skip).

**Header row** (`display:flex; align-items:baseline; gap:10px; margin-bottom:10px`):
- Speaker name — monospace 12px, `letter-spacing:0.16em`, `#8fe9f2`.
- Affiliation / channel — monospace 10px, `letter-spacing:0.12em`, `#5c6b78`.
- Advance hint, right-aligned (`margin-left:auto`) — monospace 10px, `letter-spacing:0.14em`, `#55d6e8`, bobbing animation.

**Body**: monospace 15px, `line-height:1.65`, `#dfe7ec`, `text-wrap:pretty`, `min-height:50px` (so the panel doesn't grow line by line as text types). Caret `▌` in `#55d6e8` appended while typing, blinking `caretBlink` 1s step-end infinite (visible 0–55%).

**Reply list** — rendered only when the current node is a choice node and its text has finished typing. Container: `display:flex; flex-direction:column; gap:6px; margin-top:14px;` with a 1px top border `rgba(85,214,232,0.14)` and `padding-top:12px`. Each row:
- `display:flex; align-items:center; gap:10px; padding:7px 10px; border-radius:4px;`
- fill `rgba(85,214,232,0.05)`, border 1px `rgba(85,214,232,0.14)`
- hover: fill `rgba(85,214,232,0.14)`, border `rgba(85,214,232,0.4)`
- key hint (`1`,`2`,`3`) monospace 10px `letter-spacing:0.1em` `#f2c14e`; label monospace 13px `#c7d0d8`.

### Bust placeholder
210×230, striped fill `repeating-linear-gradient(135deg,#141a21 0 6px,#1a222b 6px 12px)`, 1px border `rgba(85,214,232,0.18)` on top/left/right only. Replace wholesale with character art (transparent PNG, bottom-cropped at the waist/chest). Keep the 42px overlap and the 6px top corner radius if the art has a hard edge; art with a soft silhouette needs no border at all.

---

## Interactions & behaviour

- **Typewriter**: one character every **28ms**, driven by a single interval. Punctuation is not given extra dwell in the prototype; add it if the game's writing wants it.
- **Advance / skip** (click anywhere on the panel; wire `Space`/`E` to the same handler):
  - text still typing → jump to the full line (skip), do not advance the node.
  - text complete → move to the next line.
  - last line of a node → shows the reply list instead of advancing; selection drives the next node.
- **Advance hint label** reflects state: `SKIP ▾` while typing, `SPACE ▾` when a next line exists, `END ▾` on the last line. Animation `advBob` — 1.4s ease-in-out infinite, `translateY(0 → 3px → 0)`.
- **Bust visibility** is a boolean per speaker (`showBust`). Show it whenever the speaker has portrait art; hide it for voice-only / ship-AI speakers. Hiding it changes nothing else about the layout — the panel stays at bottom:96px.
- Reply rows are hover-highlighted only; no keyboard focus ring exists in the prototype. Add proper focus/selection states and gamepad navigation when implementing.

## State

Per active conversation:
- `nodeId` — current dialogue node.
- `lineIndex` — which line of the node is showing.
- `charCount` — characters revealed; `charCount >= line.text.length` means complete.
- `showBust` — from the speaker's data, not player state.

Data each line must supply: `{ speaker, affiliation, text }`. A node's final line may carry `choices: [{ key, label, nextNodeId }]`.

Sample copy in the prototype (Haller, Salvage Guild · CH 7) is placeholder — three lines followed by three replies.

## Design tokens

Colours
- Panel fill `rgba(16,21,27,0.9)`; border `rgba(85,214,232,0.22)`.
- Speaker name `#8fe9f2`; affiliation `#5c6b78`; body text `#dfe7ec`; reply label `#c7d0d8`.
- Cyan accent (caret, hint, reply chrome) `#55d6e8`; amber key hints `#f2c14e`.
- Background (game) `#0a0d12`.

All pulled from the existing Corporate/neutral HUD palette in `STYLE_GUIDE.md` — no new hues.

Typography
- All in-panel text is monospace (`ui-monospace, Menlo, monospace`): 10px hints, 12px speaker, 13px reply labels, 15px body.
- Letter-spacing: 0.16em speaker, 0.14em advance hint, 0.12em affiliation, 0.1em key hints.

Geometry
- Radius 6px panel / 4px reply rows; padding 18px 24px panel, 7px 10px rows; gaps 6px rows, 10px header.
- Anchor: 28px side insets, 96px bottom offset, −42px bust overlap.

Timing
- Typewriter 28ms/char; caret blink 1s; advance bob 1.4s.

## Files
- `Dialogue Box.dc.html` — prototype; 1C is the third option in the file. Template markup first, then the logic class holding the sample lines, typewriter interval, and advance handler.
- `game-screenshot-context.png` — in-game backdrop used for placement checks.
- `STYLE_GUIDE.md` — project-wide palette and construction rules.
- `support.js` — runtime for the `.dc.html` format; needed only to open the prototype in a browser, not part of the design.

Open `Dialogue Box.dc.html` in a browser with `support.js` alongside it to view.

## Open questions
- Keybinds: confirm advance key(s) and whether replies are number-key selectable as the amber hints imply.
- Does the SYSTEMS panel / cargo chip dim or hide while a conversation is open, or stay fully lit as shown?
- Portrait art spec: final bust dimensions, crop line, and whether it animates (talk cycle, blink) or is static.
- No audio design: typewriter tick, line-advance, and reply-confirm sounds are unspecified.
