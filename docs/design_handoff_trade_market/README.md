# Handoff: Trade Market Screen ("Exchange Floor v2", option 2a)

## Overview
Replacement for the game's current trade UI, which is a flat list of Buy/Sell rows overlaid on the space view. The new screen is a **full-screen station market**: it takes over the whole viewport when the player opens Trade at a station, and it must feel busy even when the player holds nothing and few materials are listed.

It does three jobs:
1. Trade any number of materials without the layout shrinking as the material list grows.
2. Show a **living economy** — prices drift on their own, the player's trades move the local price, and events at other stations move it too.
3. Show the player where the arbitrage is (same material priced at nearby stations).

This design is expected to be superseded, or complemented, by a walk-around multiplayer market later. Build it so the price model is separate from the UI — the model should survive that change.

## About the Design Files
`Trade Market.dc.html` (plus `support.js`, which is only the harness that renders it) is a **design reference written in HTML**. It is a prototype of look and behavior, not production code to lift. Recreate it in the game's existing environment and rendering stack, using the game's established UI patterns. If the project has no UI layer for screens like this yet, pick the framework that fits the engine and implement it there.

Open `Trade Market.dc.html` in a browser to see it live. The top section is **2a — the approved design**. Below it, under "TURN 1 · ARCHIVED", is the earlier card-grid version, kept only for reference — **do not build the archived one.**

## Fidelity
**High fidelity.** Colors, type sizes, spacing and states below are final and taken from the prototype. The economy numbers (decay rates, spill factors) are tuned for demo readability, not for game balance — treat them as a starting point and expect design to retune.

The design canvas is **1600 × 900**. Treat that as the reference resolution; the layout is a three-column flex row and scales by giving the centre column the slack.

---

## Screen: Station Exchange (full screen)

Entered with `T` at a station, exited with `T`. Background is the station's own palette — the mock uses Corporate (see STYLE_GUIDE.md); Pirate/Ancient stations should re-skin the accent hue only, keeping the same structure.

### Layout (1600 × 900, top to bottom)

| Band | Height | Notes |
|---|---|---|
| Header | 76px | padding `22px 34px 16px` |
| Ticker | 38px | 1px top/bottom border `rgba(85,214,232,0.14)` |
| Body | 756px | `display:flex; gap:20px; padding:20px 34px` |
| Footer hint bar | 34px | absolutely positioned at the bottom |

Body columns:
- **Left — material list**: `width:440px; flex-shrink:0`
- **Centre — focus panel**: `flex:1; min-width:0`, a vertical stack with `gap:14px`
- **Right — rail**: `width:330px; flex-shrink:0`, vertical stack with `gap:14px`

Two full-bleed background layers sit behind everything (`position:absolute; inset:0`):
1. `radial-gradient(ellipse 1100px 700px at 12% 100%, rgba(42,90,100,0.20), transparent 62%), radial-gradient(ellipse 900px 600px at 92% 0%, rgba(60,72,88,0.24), transparent 60%)`
2. A 96px grid at `opacity:0.5`: `repeating-linear-gradient(90deg, rgba(85,214,232,0.05) 0 1px, transparent 1px 96px)` and the same at `0deg` with `rgba(85,214,232,0.04)`

### Header
- Left: station name, 23px / weight 600, `#f0f6f8`. Beside it, monospace 12px `#5f6d78`, letter-spacing 0.08em: `SECTOR 04 · {n} TRADERS ON DECK` (n is derived from occupied berths — it is flavour, but it must move).
- Right: **CREDITS** label (monospace 10.5px, `#5f6d78`, letter-spacing 0.12em) over the value (monospace 22px, `#f2c14e`); then **HOLD {used} / {capacity}** over a 180 × 7px bar, track `rgba(255,255,255,0.07)` radius 4, fill `#55d6e8`.

### Ticker
Full-width strip, background `rgba(6,9,13,0.7)`, scrolling right-to-left, 60s linear loop, contents duplicated so the loop is seamless.
- Fixed chip at the left, 120px wide, **opaque** background (`#0a0d12` tinted with `rgba(85,214,232,0.10)`), 1px right border `rgba(85,214,232,0.2)`, label `LIVE FEED` monospace 11px `#8fe9f2`. It must be opaque — ticker items scrolling under a translucent chip was a bug in an earlier pass.
- Items: monospace 12.5px, `padding: 0 26px`, `white-space:nowrap`. One item per material — `IRON  41 cr  ▲ +3` — coloured by direction, plus a few event strings (`CDF CONVOY INBOUND · TITANIUM DEMAND UP`, `BERTH B-06 CLEARED`, `PIRATE ACTIVITY REPORTED · SECTOR 07`).

### Left column — material list
This is the answer to "how do we add more materials without shrinking things". Cards stop working past about six; rows never do.

Panel: `background:rgba(16,20,26,0.6)`, 1px border `rgba(255,255,255,0.07)`, flex column, `min-height:0`.
1. **Category tabs**, `padding:12px 12px 10px`, `gap:6px`, wrapping. Each tab monospace 11px, letter-spacing 0.06em, `padding:6px 11px`, no border. Selected: background `#55d6e8`, text `#0a0d12`. Unselected: background `rgba(255,255,255,0.04)`, text `#8b98a4`. Labels carry counts: `All (14)`, `Ore (6)`, `Refined (4)`, `Volatile (3)`, `Tech (1)`. Categories are derived from the material data, not hard-coded.
2. **Column header row**, grid `1.5fr 0.9fr 0.7fr 0.8fr`, monospace 10px letter-spacing 0.12em `#4e5a64`: `MATERIAL | PRICE | 24H | TREND`. 1px bottom border `rgba(255,255,255,0.07)`.
3. **Scrolling row list**, `flex:1; min-height:0; overflow-y:auto`. Row height **52px**, same 4-column grid, `padding:0 14px`, 1px bottom border `rgba(255,255,255,0.04)`, 2px left border (transparent, or the material colour when selected).
   - Colour chip 8 × 8px (material colour), then name 14px (`#c8d3db`, `#f0f6f8` when selected) with the category beneath it in monospace 9.5px `#4e5a64`.
   - If the player holds any, a pill: monospace 10px `#8fe9f2`, 1px border `rgba(85,214,232,0.3)`, `padding:1px 5px`, e.g. `50u`.
   - Price monospace 14px `#dbe3ea`; 24h delta monospace 11.5px, green `#6fe3a0` up / red `#e07a6a` down, prefixed `▲ +` / `▼ `.
   - Trend: 56 × 20px sparkline of the last 14 samples, 1.3px stroke in the material colour.
   - Selected row background `rgba(85,214,232,0.10)`; hover `rgba(255,255,255,0.05)`.
4. **Footer**: monospace 10.5px `#5f6d78`, `{shown} of {total} commodities`.

### Centre — focus panel
Top card: `flex:1`, background `rgba(16,20,26,0.6)`, 1px border `rgba(255,255,255,0.07)`, **2px top border in the selected material's colour**, `padding:20px 24px`.
- Material name 34px / 600 `#f0f6f8`; under it monospace 11px `#5f6d78`: `{CATEGORY} · {n}u traded this shift`.
- Right-aligned price: monospace **44px** `#f0f6f8`, then `cr/u` monospace 13px `#5f6d78`, then the 24h delta monospace 17px in its direction colour.
- **Chart**: full-width SVG, `viewBox 0 0 900 200`, `preserveAspectRatio:none`, flexing to fill. Area fill = material colour at `opacity:0.10`; line = material colour, 2px, round joins. Plots the full 26-sample history, min/max normalised.
- Stats row, monospace 10.5–11px: `SUPPLY` + a 150 × 6px bar (green `#6fe3a0` glut / amber `#f2c14e` steady / red `#e07a6a` scarce) with the word label; `RANGE {lo}–{hi} cr`; `STATION PAYS {sell} cr sell`; right-aligned, the live pressure line (`Market steady` / `Under upward pressure +4.2%`).

Trade bar: background `rgba(16,20,26,0.75)`, 1px border `rgba(255,255,255,0.07)`, `padding:16px 24px`, row with `gap:22px`.
- **QUANTITY** chips `10u / 25u / 50u / 100u`, monospace 12px, `padding:8px 14px`. Selected: background `rgba(85,214,232,0.2)`, border `rgba(85,214,232,0.5)`, text `#8fe9f2`. Unselected: `rgba(255,255,255,0.04)` / `rgba(255,255,255,0.1)` / `#8b98a4`.
- **IN HOLD** block, separated by a 1px left divider: label plus `50u in hold` or `none in hold` (14px `#c8d3db`).
- Right: **BUY** and **SELL**, monospace 13px, `padding:14px 26px`. Buy enabled `rgba(85,214,232,0.12)` / border `rgba(85,214,232,0.45)` / `#8fe9f2`; sell enabled `rgba(242,193,78,0.10)` / `rgba(242,193,78,0.4)` / `#f2c14e`. Labels carry the total: `BUY · 4,050 cr`, `SELL · 2,000 cr`.
  - **Disabled states are part of the design, not decoration.** When the quantity can't be afforded or won't fit, the button greys (`rgba(255,255,255,0.03)` / `rgba(255,255,255,0.1)` / `#4e5a64`, `cursor:not-allowed`) and its label states the reason: `HOLD FULL`, `NOT ENOUGH CREDITS`, `NOTHING TO SELL`. A click that silently does nothing was a bug we fixed; don't reintroduce it.

**YOUR IMPACT** banner, shown after the player trades: background `rgba(85,214,232,0.07)`, 1px border `rgba(85,214,232,0.25)`, `padding:12px 20px`. Label monospace 10.5px `#8fe9f2`; message 13.5px, e.g. *"Your 100u buy lifted Copper +6.0% here"*; right-aligned spillover summary 12.5px `#8b98a4`, e.g. *"spillover +2.4% at Ashgrave Hulk · +1.7% at Kestrel Yards"*.

### Right rail — three panels
All three share `rgba(16,20,26,0.7)` / 1px `rgba(255,255,255,0.07)` / `padding:14px 16px`. **Their sizing is load-bearing**: the rail is a fixed-height flex column, so each panel gets an explicit flex share, `min-height:0`, `overflow:hidden`, and its own internal `overflow-y:auto` list. Content-sized panels here collapsed the flexible one and clipped text mid-line — twice. Keep the shares.
- **NEARBY MARKETS · {material}** — `flex:1.3 1 0`. Sub-line 11.5px `#5f6d78`: "Prices react to your trades, strongest within 2 jumps." One entry per station: name 13.5px, its price monospace 13px, the difference vs. here monospace 12px (green > +4%, red < −4%, else `#8b98a4`), then a second line with jump distance, a 4px comparison bar, an arbitrage flag (`sell here` / `buy here` / `in line`, flagged in `#f2c14e` beyond ±8%), and `reacting to you` in `#8fe9f2` while spillover is active.
- **MARKET FORCES** — `flex:1 1 0`. Up to 3 live events, each: material colour square, the sentence (12.5px `#c8d3db`, e.g. *"Rell Freeport dumped a full hold of cobalt"*), a meta line (monospace 9.5px `#4e5a64`: `5 jumps out · 2 ticks ago`), and the price effect right-aligned in green/red. Rows fade with age (`opacity 1 → 0.45`). Header sub-line: `{n} active price drivers across 5 markets` or `No outside pressure right now`.
- **FLOOR ACTIVITY** — fixed `flex:0 0 176px`. Rolling log of NPC/other-trader actions, newest first, each row a monospace timestamp plus a 12.5px line, older rows dimmed. Cyan `#8fe9f2` for buys, amber `#f2c14e` for sells, `#a8b4bd` for movement.

### Footer hint bar
Monospace 11.5px `#5f6d78`, letter-spacing 0.06em: `[↑/↓] SELECT MATERIAL`, `[1-4] QUANTITY`, `[B] BUY  [S] SELL`, `[M] NEARBY MARKETS`; right-aligned `{clock} · NEXT PRICE TICK {n}s` in `#8fe9f2`.

---

## The economy model (the important part)

Implement this as a **simulation service, not screen state** — the screen only reads it. It should keep running while the player is elsewhere, and it is what a future multiplayer market would plug other players into.

### Per-material data
`{ key, name, category, basePrice, volatility, color }`. The prototype ships 14: Iron 40, Copper 80, Nickel 100, Titanium 180, Glass 120, Cobalt 210, Platinum 340, Silicon 95, Polymer 150, Ceramics 175, Circuitry 420, Coolant 130, Hydrogen 60, Deuterium 280 (credits per unit). Categories: Ore, Refined, Volatile, Tech.

### Tick
One tick every **1.8s** in the prototype. Per tick, per material:
1. **Drift** — random walk on the 26-sample history: `next = last + (rand() - 0.48) * volatility`, clamped to `[0.55 × base, 1.6 × base]`. The slight negative bias keeps prices from running away.
2. **Pressure decay** — `pressure *= 0.88`, dropped below 0.001.

**Displayed price = `round(history.last × (1 + pressure))`.** Station sell price (what the station pays the player) is **50% of buy price** throughout.

### Player pressure
On a trade of `q` units in direction `dir` (+1 buy, −1 sell): `pressure[material] += dir × q × 0.0006`. So 100u moves the local price ~6%, decaying over roughly a dozen ticks. Buying raises the price; selling lowers it.

### Spillover to nearby stations
Five neighbours, each with a jump distance and a base price multiplier: Kestrel Yards (2, ×0.93), Halcyon Drift (3, ×1.09), Rell Freeport (5, ×0.84), Ashgrave Hulk (1, ×1.16), Vosk Refinery (4, ×0.98).

A neighbour's shown price is `round(localPrice × multiplier × (1 + pressure × reach))`, where **reach** is 0.40 at 1–2 jumps, 0.20 at 3, 0.08 at 4+. That is the "one big economy" behaviour: what the player does here ripples outward, strongest next door.

### Outside events (other places affecting this market)
Each tick there is a **55% chance** an event fires: pick a random neighbour station and a random material, pick an event type, and apply `pressure[material] += direction × (0.02 … 0.07) × reach(station)` — the same distance falloff, so a strike five jumps away barely registers and a blockade next door bites.

Event types (direction in brackets): refinery strike halted output (+), dumped a full hold (−), convoy raided (+), surplus auction opened (−), fleet contract signed (+), reopened its seams (−), blockade lifted (−).

Events are kept for display with an age counter, capped at 3 in the panel. In a live game these should be real events in the world sim (a raided convoy should be a convoy that was actually raided), not random strings — the UI is already shaped for that.

### Multiplayer note
The pressure term is deliberately additive and source-agnostic. Other players' trades should feed the same `pressure` accumulator as the local player's; the only UI question then is whether the FLOOR ACTIVITY log names them.

## State
Screen state: `selectedMaterial` (key), `selectedCategory` (string, default `All`), `quantity` (10/25/50/100, default 50), `lastImpact` (message shown in the banner, cleared on screen exit).

Player state: `credits`, `hold` (used units), `holdCapacity` (160 in the mock), `cargo` (map material → units).

World state (the service above): `priceHistory` (26 samples per material), `pressure` (map material → float), `events` (recent, with age), `tickCounter`.

## Interactions
- Clicking a list row selects it; the focus panel, nearby-markets panel and trade bar all follow the selection.
- Category tabs filter the list only; selection persists even if the selected material is filtered out of view.
- Quantity chips set the trade size; totals on both buttons update immediately.
- BUY: fails if `credits < price × q` or `hold + q > capacity` — the button is disabled and labelled with the reason before the click.
- SELL: fails if held units < q, same treatment.
- A successful trade updates credits, hold, cargo and pressure, and writes the YOUR IMPACT banner.
- Ticker: 60s linear infinite marquee. Row hover: `rgba(255,255,255,0.05)`. No other motion — the movement should come from data changing, which is what makes the screen feel busy with an empty hold.

## Design tokens
Corporate station palette (see STYLE_GUIDE.md for the other factions):

| Token | Value |
|---|---|
| Screen background | `#0a0d12` |
| Panel background | `rgba(16,20,26,0.6–0.75)` |
| Panel border | `rgba(255,255,255,0.07)` |
| Primary text | `#f0f6f8` |
| Secondary text | `#c8d3db` / `#a8b4bd` |
| Muted / labels | `#5f6d78`, `#4e5a64` |
| Accent cyan | `#55d6e8`, light `#8fe9f2`, deep `#2a8fa3` |
| Warm accent | `#f2c14e` |
| Price up | `#6fe3a0` |
| Price down | `#e07a6a` |
| Material colours | Iron `#9fb0bd`, Copper `#e08b4c`, Nickel `#a8c0c8`, Titanium `#cbd6e0`, Glass `#8fe9f2`, Cobalt `#7f9fd6`, Platinum `#e2e8ee`, Silicon `#b6c2cc`, Polymer `#c9a3e0`, Ceramics `#dfc9a8`, Circuitry `#6fe3a0`, Coolant `#79cfe0`, Hydrogen `#8fb8e8`, Deuterium `#f2c14e` |

Type: UI sans (system stack in the mock) for names and prose; **monospace for every number, label and key hint** — that split is deliberate and carries most of the screen's character. Sizes in use: 44 / 34 / 23 / 17 / 14.5 / 14 / 13.5 / 12.5 / 11.5 / 11 / 10.5 / 9.5px. Letter-spacing 0.06–0.14em on uppercase monospace labels only.

Spacing: 34px screen gutters, 20–24px panel padding, 14–20px gaps between panels, 6–11px inside them. Corners are square throughout except the hold bar (4px) and status dots.

## Assets
None. Everything is CSS gradients, borders and inline SVG paths generated from price data. No images or icon fonts are required.

## Files
- `Trade Market.dc.html` — the design. Top section = **2a, the approved screen**; the section below it is the archived first exploration, for context only.
- `support.js` — rendering harness for the HTML prototype. Not part of the design; ignore it when implementing.
- `STYLE_GUIDE.md` — the wider art style guide for the game (faction palettes and construction rules), for re-skinning this screen at Pirate/Ancient/neutral stations.
