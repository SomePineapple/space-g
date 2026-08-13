# Story Maker

An offline authoring tool for SpaceG's map events, NAVOS lines and captain's
log entries. Open `story-maker/index.html` in a browser — no build step, no
server, no dependencies. Everything it produces is one JSON file.

It is an **authoring tool only**. Nothing in the Godot project reads its output
yet; the importer gets written when there is real content and a quest runtime to
feed it. The schema below is the contract that importer will be written against.

---

## Using it

| | |
| --- | --- |
| **V** | Select / move |
| **E** | Place an event |
| **L** | Link two events — click the one that comes *first*, then the one it leads to |
| **P** | Pen: click for corners, drag for freehand. **Enter** closes, **Esc** cancels, **Backspace** undoes a point |
| **N** | Place a note |
| **F** | Frame everything |
| **Del** | Delete the selection |
| **Ctrl+Z / Ctrl+Shift+Z** | Undo / redo |
| **Ctrl+S** | Save |

Pan with middle-drag, space-drag, alt-drag, or by dragging empty space with the
select tool. Zoom with the wheel.

An event's dashed ring is its **trigger radius** — how close the player has to
get. Drag an area's handles to reshape it; drag its body to move the whole
thing.

### Links and prerequisites

A link is drawn from the thing that happens first to the one that follows.
**Required** links (solid) are gates: the source must have happened. **Optional**
links (dashed) are just references on the board and gate nothing. When several
required links point at the same event, that event's `prereq_mode` decides
whether *all* of them or *any one* is enough.

**Either end can be an event or a pen area.** A required link *from* an area
means "the player must have entered this region first" — an area is a place, so
that is the only gate it can express. An area can never be the *target* of a
gate (it has nothing to complete), so those links are references and the tool
forces `required: false` on them.

Area links attach to the diamond at the area's centroid; click that diamond with
the **L** tool, or use the "Link this to…" picker in either inspector.

Setting an option's **Leads to** automatically draws a `choice` link if one is
not already there, so the board and the choice data cannot disagree.

The **Checks** panel flags authoring mistakes — missing titles, options with no
outcome, duplicate clip ids, and prerequisite loops that could never unlock.

### Saving

Three layers, because losing a story map is expensive:

1. **Autosave** to browser storage after every edit. Reopening the page restores
   the last session automatically.
2. **A real file.** In Chrome/Edge, `Save as` picks a file once and every later
   `Save` writes straight into it; the page remembers that file across reloads
   (one click to re-grant permission after a restart).
3. **Download fallback** in Firefox/Safari — `Save` downloads the `.json`, `Open`
   uses a file picker.

The file on disk is the source of truth. Autosave is a crash net, and the status
line under the buttons always says which file you are attached to.

Keep authored maps in `story-maker/data/` so they sit next to the tool and
travel with the repo. `data/example-map.json` is a two-event sample — open it to
see every field filled in, including a choice that gates a follow-up event.

---

## File format

`schema: "space-g.story-map"`, `version: 1`. All coordinates are the map's own
abstract units — the tool does not assume a relationship to Godot world pixels.
Fixing a scale is a decision for the importer, not for the author.

```jsonc
{
  "schema": "space-g.story-map",
  "version": 1,
  "id": "map_ab12c",
  "name": "Chapter 1 — the graveyard",
  "updated": "2026-08-13T10:04:00.000Z",

  "map": {
    "grid": 250,
    "background": null,              // or {name, src (data URI), x, y, w, h, opacity}
    "view": { "x": 0, "y": 0, "zoom": 1 }
  },

  "events": [ /* see below */ ],
  "links":  [ /* see below */ ],
  "areas":  [ /* see below */ ],
  "notes":  [ /* see below */ ]
}
```

### Event

```jsonc
{
  "id": "evt_k3f9a",              // stable; links and options refer to it
  "title": "Distress call — Kestrel",
  "type": "distress_signal",      // free text; the suggestions are just a datalist
  "x": -1200, "y": 340,
  "radius": 500,                  // trigger distance, map units
  "color": "",                    // blank = derive from type
  "once": true,
  "prereq_mode": "all",           // "all" | "any", over this event's required links
  "tags": ["chapter1", "optional"],

  "description": "Text the player reads when the event opens.",

  "options": [                    // 0–3 choices
    {
      "id": "opt_x1",
      "label": "Answer the signal",
      "outcome": "Text shown after this choice.",
      "navos": { "clip_id": "Distress_03", "text": "Subtitle for that clip." },
      "log_text": "Captain's log line written by this choice.",
      "leads_to": "evt_9wq2z"     // event id, or ""
    }
  ],

  "navos": {                      // ambient lines, not tied to a choice
    "approach": [ { "id": "vo_1", "clip_id": "Kestrel_01", "text": "Signal strengthening." } ],
    "inside":   [],
    "depart":   []
  },

  "log": {                        // written when the event resolves
    "title": "The Kestrel",
    "text": "Answered a distress call near the graveyard edge."
  },

  "notes": "Author's scratch notes. Never shown in game."
}
```

`clip_id` is meant to match a key in `audio/voice lines/.../voice_lines.gd`
(`CLIPS` / `SUBTITLES`), so the exported text can double as the subtitle. It is
optional — a line with text and no clip id is a written line waiting to be
recorded.

### Link

```jsonc
{
  "id": "lnk_22bd",
  "from": "evt_k3f9a",            // happens first
  "from_type": "event",           // "event" | "area"
  "to":   "evt_9wq2z",
  "to_type": "event",             // "event" | "area"
  "kind": "sequence",             // "sequence" | "choice" | "reference"
  "required": true,               // true = gate; false = board reference only
  "label": "",
  "color": ""
}
```

`from_type`/`to_type` say which collection the id lives in. They are always
written, and a file that predates them is repaired on load by looking the id up
in both collections. `required` is only ever `true` when `to_type` is `"event"`.

### Area and note

```jsonc
{ "id": "area_7", "name": "Pirate territory", "points": [[x,y], …],
  "closed": true, "fill": "#e0574f", "stroke": "#e0574f",
  "opacity": 0.16, "note": "Patrols thicken toward the centre." }

{ "id": "note_3", "x": 0, "y": -900, "text": "start here", "color": "#c8d6e2", "size": 16 }
```

---

## Notes for whoever writes the importer

- **Ids are the join.** `links.from/to` reference `events[].id` or `areas[].id`
  according to `from_type`/`to_type`; `options[].leads_to` is always an event.
  The tool refuses to save a dangling reference — it clears them on load — so an
  importer can treat every id as resolvable, but should still fail loudly rather
  than silently skipping.
- **A required link is the only gate.** `prereq_mode` only chooses between AND
  and OR over an event's *required* incoming links. Optional links carry no
  gameplay meaning at all. A required link whose source is an area means the
  player must have entered that area, which is the one runtime check areas
  imply — everything else about an area is authoring context.
- **Nothing here is a Godot Resource yet.** Per `CLAUDE.md`, the resource
  classes should be introduced when a system genuinely benefits — that means
  when a quest runtime exists to consume them, not before.
- **The background image is embedded as a data URI**, which is why the tool
  warns above 6 MB. If maps start getting heavy, switch it to a relative path
  and load the file next to the map.
