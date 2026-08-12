# Handoff: Controls Tutorial (first-time control hint)

## Overview
A corner HUD panel that teaches the player a control the first time it becomes relevant — e.g. "To move and rotate, use WASD." It shows the key(s) as key-cap graphics, waits for the player to actually press each one, then auto-advances to the next control tip. Once every tip has been shown, it dismisses itself and does not resurface on later sessions (skippable and persisted per-player).

## About the design files
`Controls Tutorial.dc.html` is a design reference authored in a bespoke HTML component format used by the design tool. It shows intended look and behaviour; it is not production code to copy. Recreate it in the game's existing HUD/UI layer using that layer's established patterns (React/Vue/engine UI/etc). All layout is plain CSS flexbox/grid and absolute positioning, so it maps directly.

## Fidelity
**High-fidelity.** Colours, typography, geometry, and interaction behaviour are final-intent. Sample tip copy (WASD / SPACE / E) is placeholder — swap in the game's actual first-run control sequence and real key bindings (including remapped keys / gamepad).

---

## Layout

Panel is anchored to the top-right of the screen, independent of other HUD elements:

```
screen
└── panel (position:absolute; top:24px; right:24px; width:380px)
    ├── header row (eyebrow "NEW CONTROL" + "SKIP ✕")
    ├── instruction text
    ├── key formation (varies per tip — grid for WASD, single cap for E, wide bar for SPACE)
    └── footer row (hint text + step progress dots)
```

- Fill `rgba(20,26,33,0.82)` with `backdrop-filter: blur(6px)`, 1px border `rgba(85,214,232,0.28)`, `border-radius:6px`, `padding:22px 24px 20px`, drop shadow `0 8px 24px rgba(0,0,0,0.4)`. This matches the existing dialogue/HUD glass-panel chrome (see `STYLE_GUIDE.md` and the Dialogue Box handoff) rather than a standalone modal style — it should read as part of the same UI system, not an overlay dialog.
- No screen-dimming backdrop — gameplay stays fully visible/interactive behind it.
- Panel width fixed at 380px; height is intrinsic to content (varies slightly per tip's key formation).

### Header row
`display:flex; justify-content:space-between; margin-bottom:14px`
- Eyebrow "NEW CONTROL" — monospace 11px, `letter-spacing:0.16em`, `#f2c14e`.
- "SKIP ✕" — monospace 11px, `#5c6b78`, hover `#c7d0d8`, cursor pointer. Clicking dismisses the whole tutorial immediately (same as finishing it).

### Instruction text
16px, `line-height:1.5`, `#dfe7ec`, `margin-bottom:18px`, `min-height:24px` (prevents reflow between tips of different line counts).

### Key formation
Key caps are 56×56px, `border-radius:8px`, monospace bold 19px, centered content, `transition: all .15s`.
- **Unpressed**: border 1px `rgba(85,214,232,0.3)`, fill `rgba(85,214,232,0.06)`, text `#8fa0ab`, slow pulsing glow (`box-shadow` 0 → 6px spread `rgba(85,214,232,0.35)` → 0, 1.8s ease-in-out infinite) to draw the eye.
- **Pressed**: border `#55d6e8`, fill `rgba(85,214,232,0.2)`, text `#8fe9f2`, static glow `0 0 10px rgba(85,214,232,0.3)`, pulse stops. A small ✓ badge appears top-right of the cap.
- WASD formation: CSS grid, 3 columns × 2 rows of 56px cells, 6px gap. W at column 2/row 1; A/S/D at columns 1–3/row 2.
- Single-key tip (e.g. E): one 56×56 cap, centered.
- Wide-key tip (e.g. SPACE): one 200×56px cap, same colors, 15px letter-spaced label instead of a single glyph.

### Footer row
`display:flex; justify-content:space-between`
- Hint text, monospace 10px `#5c6b78`: reads "PRESS THE HIGHLIGHTED KEY(S) TO CONTINUE" while waiting, "GOT IT ▸" once the current tip's keys are all pressed (during the advance delay).
- Progress dots, one per tip in the sequence: 6px circles, `#55d6e8` (current), `rgba(85,214,232,0.5)` (completed), `rgba(85,214,232,0.15)` (upcoming).

---

## Interactions & behaviour

- On mount, the tutorial checks whether the player has already completed it (persisted flag). If so, it does not render.
- Each tip lists one or more required keys. A real `keydown` listener (not click) marks a key as pressed the first time it's seen; already-pressed keys are ignored.
- When every key in the current tip has been pressed, wait **550ms** (lets the player see the confirmed ✓ state) then advance to the next tip, resetting pressed-state for the new tip's keys.
- After the last tip's keys are all pressed (or the player clicks "SKIP ✕" at any point), persist "seen" and hide the panel. It should not reappear for that player unless the game explicitly resets tutorial progress (e.g. a settings option "Replay tutorials").
- Tips are shown once each, in a fixed sequence, the first time the panel is triggered — not re-triggered per control across the whole game. If the intent is instead "show this tip the first time this specific control becomes relevant" (e.g. WASD at the very start, SPACE the first time the player picks up a weapon), each tip's persisted-seen flag should probably be tracked independently and the panel invoked separately per control at its first relevant moment — confirm which model the game wants (see Open Questions).
- Sample sequence in the prototype: WASD (move/rotate) → SPACE (fire) → E (interact). Replace with the game's real onboarding sequence and bindings.

## State
- `stepIndex` — index into the tip sequence.
- `pressed` — set of keys pressed so far within the current tip.
- `dismissed` — true once the whole sequence is complete or skipped; drives visibility.
- Persisted (e.g. localStorage / player save data): a single "controls tutorial seen" boolean, or one per tip if tips fire independently (see Open Questions).

Each tip's data shape: `{ id, keys: string[], text: string }`.

## Design tokens

Colours (from the existing Corporate/neutral HUD palette, see `STYLE_GUIDE.md`)
- Panel fill `rgba(20,26,33,0.82)`; border `rgba(85,214,232,0.28)`.
- Eyebrow label `#f2c14e`; body text `#dfe7ec`; muted/hint text `#5c6b78`.
- Key cap accent (unpressed border/fill, progress dots) `#55d6e8` family at varying opacity; pressed-state text `#8fe9f2`.

Typography
- Monospace throughout (`ui-monospace, Menlo, monospace`): 11px eyebrow/skip, 16px instruction, 19px key glyph, 15px wide-key label, 10px footer hint.
- Letter-spacing: 0.16em eyebrow, 0.1em skip, 0.08em footer hint.

Geometry
- Panel radius 6px; key cap radius 8px; padding 22px 24px 20px; key grid gap 6px.
- Anchor: top:24px, right:24px; panel width 380px fixed; key caps 56×56px (200×56 for wide keys).

Timing
- Advance delay after a tip's keys are all pressed: 550ms.
- Unpressed key pulse: 1.8s ease-in-out infinite.

## Assets
None — no external imagery, all key caps and chrome are CSS/HTML. `controls-tutorial-screenshot.png` shows the panel over the placeholder gameplay backdrop at its idle (WASD) tip.

## Files
- `Controls Tutorial.dc.html` — prototype. Template markup first, then the logic class holding the tip sequence, keydown listener, and advance/skip/persistence logic.
- `STYLE_GUIDE.md` — project-wide palette and construction rules.
- `support.js` — runtime for the `.dc.html` format; needed only to open the prototype in a browser, not part of the design.

Open `Controls Tutorial.dc.html` in a browser with `support.js` alongside it to view. It has a `forceShow` toggle (design-tool preview only) that ignores the persisted "seen" flag so the sequence can be replayed — this is not gameplay-facing and shouldn't be built into the real game.

## Open questions
- Should tips fire as one fixed opening sequence, or should each control tip trigger independently the first time that specific control becomes relevant during play (e.g. SPACE-to-fire only shown once the player has a weapon)? The prototype implements the fixed-sequence model.
- Real key bindings and remapping: the prototype listens for literal `keydown` (W/A/S/D/Space/E). Production needs to read the player's actual (possibly remapped) bindings and support gamepad equivalents shown as controller glyphs instead of keycaps.
- Where is "seen" persisted — local save file, cloud profile, or per-device? Determines whether the tutorial reappears on a new device/profile.
- Does the panel need to pause or dim gameplay input while active, or should movement etc. keep working live under it as currently designed?
