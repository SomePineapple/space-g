/* state.js — the document model, undo history and a tiny event bus.
 *
 * Everything the tool knows lives in SM.doc, which is a plain JSON-safe object.
 * That is deliberate: the file on disk, the autosave copy and the in-memory
 * document are the same shape, so saving is JSON.stringify and nothing else.
 * Classic scripts, no ES modules — module imports are blocked over file://. */

window.SM = window.SM || {};

(function (SM) {
  'use strict';

  SM.SCHEMA = 'space-g.story-map';
  SM.VERSION = 1;

  /* Suggested types only — the field is free text, so a new kind of event is
     just a word, not a code change. Colours are per type unless an event
     overrides its own. */
  SM.EVENT_TYPES = [
    'distress_signal', 'bounty_board', 'derelict', 'ambush', 'trader',
    'anomaly', 'beacon', 'station', 'story_beat'
  ];

  SM.TYPE_COLORS = {
    distress_signal: '#e0574f',
    bounty_board:    '#e0a935',
    derelict:        '#8d7fd0',
    ambush:          '#d0507f',
    trader:          '#57c98a',
    anomaly:         '#35d0e0',
    beacon:          '#4f9de0',
    station:         '#c8d6e2',
    story_beat:      '#f0e6a0'
  };
  SM.DEFAULT_COLOR = '#35d0e0';

  SM.LINK_KINDS = ['sequence', 'choice', 'reference'];

  SM.eventColor = function (ev) {
    return ev.color || SM.TYPE_COLORS[ev.type] || SM.DEFAULT_COLOR;
  };

  /* ------------------------------------------------------------------ bus */

  var listeners = {};
  SM.bus = {
    on: function (name, fn) {
      (listeners[name] = listeners[name] || []).push(fn);
    },
    emit: function (name, arg) {
      (listeners[name] || []).forEach(function (fn) { fn(arg); });
    }
  };

  /* ------------------------------------------------------------------ ids */

  var counter = 0;
  SM.uid = function (prefix) {
    counter += 1;
    return prefix + '_' +
      Math.random().toString(36).slice(2, 7) +
      counter.toString(36);
  };

  /* --------------------------------------------------------- constructors */

  SM.newDoc = function (name) {
    return {
      schema: SM.SCHEMA,
      version: SM.VERSION,
      id: SM.uid('map'),
      name: name || 'Untitled map',
      updated: new Date().toISOString(),
      map: {
        grid: 250,
        background: null,               /* {name, src, x, y, w, h, opacity} */
        view: { x: 0, y: 0, zoom: 1 }   /* screen = world * zoom + (x, y)   */
      },
      events: [],
      links: [],
      areas: [],
      notes: []
    };
  };

  SM.newEvent = function (x, y) {
    return {
      id: SM.uid('evt'),
      title: 'New event',
      type: 'distress_signal',
      x: Math.round(x),
      y: Math.round(y),
      radius: 500,          /* world units — how close the player must get   */
      color: '',            /* blank = inherit from type                     */
      once: true,
      prereq_mode: 'all',   /* all | any — over this event's required links  */
      tags: [],
      description: '',
      options: [],
      navos: { approach: [], inside: [], depart: [] },
      log: { title: '', text: '' },
      notes: ''             /* author's own scratch notes, never shown in game */
    };
  };

  SM.newOption = function () {
    return {
      id: SM.uid('opt'),
      label: '',
      outcome: '',
      navos: { clip_id: '', text: '' },
      log_text: '',
      leads_to: ''          /* event id, or blank */
    };
  };

  SM.newNavosLine = function () {
    return { id: SM.uid('vo'), clip_id: '', text: '' };
  };

  /* An endpoint is an event or an area. An area as the *source* of a required
     link reads as "the player must have entered this region first"; an area as
     the target has no state to unlock, so such a link is a board reference and
     `required` is forced off (see normalize). */
  SM.newLink = function (fromId, toId, fromType, toType) {
    return {
      id: SM.uid('lnk'),
      from: fromId,
      from_type: fromType || 'event',
      to: toId,
      to_type: toType || 'event',
      kind: 'sequence',
      label: '',
      required: (toType || 'event') === 'event',  /* "must happen first" */
      color: ''
    };
  };

  SM.newArea = function (points) {
    return {
      id: SM.uid('area'),
      name: 'New area',
      points: points || [],
      closed: true,
      fill: '#35d0e0',
      stroke: '#35d0e0',
      opacity: 0.16,
      note: ''
    };
  };

  SM.newNote = function (x, y) {
    return {
      id: SM.uid('note'),
      x: Math.round(x),
      y: Math.round(y),
      text: 'Note',
      color: '#c8d6e2',
      size: 16
    };
  };

  /* ------------------------------------------------------------- document */

  SM.doc = SM.newDoc();
  SM.sel = null;            /* {type: 'event'|'link'|'area'|'note', id}      */

  SM.collection = function (type) {
    return SM.doc[type + 's'] || [];
  };

  SM.get = function (type, id) {
    var list = SM.collection(type);
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) { return list[i]; }
    }
    return null;
  };

  SM.selected = function () {
    return SM.sel ? SM.get(SM.sel.type, SM.sel.id) : null;
  };

  SM.select = function (type, id) {
    SM.sel = (type && id) ? { type: type, id: id } : null;
    SM.bus.emit('selection');
    SM.bus.emit('render');
  };

  SM.eventTitle = function (id) {
    var ev = SM.get('event', id);
    return ev ? (ev.title || '(untitled)') : '(missing event)';
  };

  /* Either kind of link endpoint, by name and by position. */
  SM.nodeTitle = function (type, id) {
    var node = SM.get(type || 'event', id);
    if (!node) { return '(missing)'; }
    return type === 'area'
      ? (node.name || '(unnamed area)')
      : (node.title || '(untitled)');
  };

  SM.areaCentre = function (area) {
    if (!area || !area.points.length) { return { x: 0, y: 0 }; }
    var x = 0, y = 0;
    area.points.forEach(function (p) { x += p[0]; y += p[1]; });
    return { x: x / area.points.length, y: y / area.points.length };
  };

  SM.nodeAnchor = function (type, id) {
    var node = SM.get(type || 'event', id);
    if (!node) { return null; }
    return type === 'area' ? SM.areaCentre(node) : { x: node.x, y: node.y };
  };

  /* Removing an event or an area has to take its links with it, and clear any
     option that pointed at it — a dangling reference is worse than a lost
     link. */
  SM.deleteObject = function (type, id) {
    var list = SM.collection(type);
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].id === id) { list.splice(i, 1); }
    }
    if (type === 'event' || type === 'area') {
      SM.doc.links = SM.doc.links.filter(function (l) {
        return !(l.from === id && (l.from_type || 'event') === type) &&
               !(l.to === id && (l.to_type || 'event') === type);
      });
    }
    if (type === 'event') {
      SM.doc.events.forEach(function (ev) {
        ev.options.forEach(function (op) {
          if (op.leads_to === id) { op.leads_to = ''; }
        });
      });
    }
    if (SM.sel && SM.sel.id === id) { SM.sel = null; }
  };

  /* An option pointing at an event implies a link on the board. Create one if
     the author has not already drawn it, so the two views cannot disagree. */
  SM.ensureChoiceLink = function (fromId, toId, label) {
    if (!fromId || !toId || fromId === toId) { return null; }
    var existing = SM.doc.links.filter(function (l) {
      return l.from === fromId && l.to === toId &&
             (l.from_type || 'event') === 'event' &&
             (l.to_type || 'event') === 'event';
    })[0];
    if (existing) { return existing; }
    var link = SM.newLink(fromId, toId, 'event', 'event');
    link.kind = 'choice';
    link.required = false;
    link.label = label || '';
    SM.doc.links.push(link);
    return link;
  };

  SM.linksInto = function (type, id) {
    return SM.doc.links.filter(function (l) {
      return l.to === id && (l.to_type || 'event') === (type || 'event');
    });
  };

  SM.linksOutOf = function (type, id) {
    return SM.doc.links.filter(function (l) {
      return l.from === id && (l.from_type || 'event') === (type || 'event');
    });
  };

  /* -------------------------------------------------------------- history */

  SM.history = { past: [], future: [] };
  var HISTORY_CAP = 80;
  var lastPush = { key: null, at: 0 };

  /* Call before mutating. `key` coalesces rapid edits of the same field, so
     typing a description does not fill the stack one keystroke at a time. */
  SM.push = function (key) {
    var now = Date.now();
    if (key && lastPush.key === key && now - lastPush.at < 900) {
      lastPush.at = now;
      return;
    }
    lastPush = { key: key || null, at: now };
    SM.history.past.push(JSON.stringify(SM.doc));
    if (SM.history.past.length > HISTORY_CAP) { SM.history.past.shift(); }
    SM.history.future.length = 0;
  };

  SM.undo = function () {
    if (!SM.history.past.length) { return false; }
    SM.history.future.push(JSON.stringify(SM.doc));
    SM.doc = JSON.parse(SM.history.past.pop());
    lastPush = { key: null, at: 0 };
    SM.afterDocSwap();
    return true;
  };

  SM.redo = function () {
    if (!SM.history.future.length) { return false; }
    SM.history.past.push(JSON.stringify(SM.doc));
    SM.doc = JSON.parse(SM.history.future.pop());
    lastPush = { key: null, at: 0 };
    SM.afterDocSwap();
    return true;
  };

  SM.afterDocSwap = function () {
    if (SM.sel && !SM.get(SM.sel.type, SM.sel.id)) { SM.sel = null; }
    SM.bus.emit('doc');
    SM.bus.emit('selection');
    SM.bus.emit('render');
    SM.bus.emit('dirty');
  };

  /* Every edit funnels through here so autosave, the canvas and the sidebar
     never have to be poked individually by whoever made the change. */
  SM.changed = function () {
    SM.doc.updated = new Date().toISOString();
    SM.bus.emit('render');
    SM.bus.emit('list');
    SM.bus.emit('dirty');
  };

  /* ---------------------------------------------------------- load / heal */

  /* Accepts anything that parses, fills in fields added after the file was
     written, and drops references that no longer resolve. A map authored by an
     older build should open, not fail. */
  SM.normalize = function (raw) {
    var doc = SM.newDoc();
    if (!raw || typeof raw !== 'object') { return doc; }

    doc.id = raw.id || doc.id;
    doc.name = raw.name || doc.name;
    doc.updated = raw.updated || doc.updated;
    doc.version = SM.VERSION;

    var m = raw.map || {};
    doc.map.grid = num(m.grid, 250);
    doc.map.background = m.background || null;
    if (m.view) {
      doc.map.view = {
        x: num(m.view.x, 0), y: num(m.view.y, 0),
        zoom: clamp(num(m.view.zoom, 1), 0.02, 8)
      };
    }

    (raw.events || []).forEach(function (e) {
      var ev = SM.newEvent(num(e.x, 0), num(e.y, 0));
      ev.id = e.id || ev.id;
      ev.title = str(e.title, ev.title);
      ev.type = str(e.type, ev.type);
      ev.radius = Math.max(0, num(e.radius, 500));
      ev.color = str(e.color, '');
      ev.once = e.once !== false;
      ev.prereq_mode = e.prereq_mode === 'any' ? 'any' : 'all';
      ev.tags = Array.isArray(e.tags) ? e.tags.map(String) : [];
      ev.description = str(e.description, '');
      ev.notes = str(e.notes, '');
      ev.log = {
        title: str(e.log && e.log.title, ''),
        text: str(e.log && e.log.text, '')
      };
      ev.options = (e.options || []).slice(0, 3).map(function (o) {
        var op = SM.newOption();
        op.id = o.id || op.id;
        op.label = str(o.label, '');
        op.outcome = str(o.outcome, '');
        op.log_text = str(o.log_text, '');
        op.leads_to = str(o.leads_to, '');
        op.navos = {
          clip_id: str(o.navos && o.navos.clip_id, ''),
          text: str(o.navos && o.navos.text, '')
        };
        return op;
      });
      ['approach', 'inside', 'depart'].forEach(function (slot) {
        var src = (e.navos && e.navos[slot]) || [];
        ev.navos[slot] = src.map(function (l) {
          var line = SM.newNavosLine();
          line.id = l.id || line.id;
          line.clip_id = str(l.clip_id, '');
          line.text = str(l.text, '');
          return line;
        });
      });
      doc.events.push(ev);
    });

    /* Areas are normalized before links, because a link may point at one. */
    (raw.areas || []).forEach(function (a) {
      var pts = (a.points || []).map(function (p) {
        return Array.isArray(p) ? [num(p[0], 0), num(p[1], 0)]
                                : [num(p.x, 0), num(p.y, 0)];
      });
      if (pts.length < 2) { return; }
      var area = SM.newArea(pts);
      area.id = a.id || area.id;
      area.name = str(a.name, area.name);
      area.closed = a.closed !== false;
      area.fill = str(a.fill, area.fill);
      area.stroke = str(a.stroke, area.stroke);
      area.opacity = clamp(num(a.opacity, 0.16), 0, 1);
      area.note = str(a.note, '');
      doc.areas.push(area);
    });

    var known = { event: {}, area: {} };
    doc.events.forEach(function (e) { known.event[e.id] = true; });
    doc.areas.forEach(function (a) { known.area[a.id] = true; });

    /* Files written before areas were linkable carry no endpoint types, so
       resolve them by looking the id up in both collections. */
    function endpointType(declared, id) {
      if (declared === 'area' || declared === 'event') { return declared; }
      return known.area[id] ? 'area' : 'event';
    }

    (raw.links || []).forEach(function (l) {
      var ft = endpointType(l.from_type, l.from);
      var tt = endpointType(l.to_type, l.to);
      if (!known[ft][l.from] || !known[tt][l.to]) { return; }
      var link = SM.newLink(l.from, l.to, ft, tt);
      link.id = l.id || link.id;
      link.kind = SM.LINK_KINDS.indexOf(l.kind) >= 0 ? l.kind : 'sequence';
      link.label = str(l.label, '');
      /* An area has nothing to complete, so it can never be gated. */
      link.required = tt === 'event' && l.required !== false;
      link.color = str(l.color, '');
      doc.links.push(link);
    });

    doc.events.forEach(function (ev) {
      ev.options.forEach(function (op) {
        if (op.leads_to && !known.event[op.leads_to]) { op.leads_to = ''; }
      });
    });

    (raw.notes || []).forEach(function (n) {
      var note = SM.newNote(num(n.x, 0), num(n.y, 0));
      note.id = n.id || note.id;
      note.text = str(n.text, '');
      note.color = str(n.color, note.color);
      note.size = clamp(num(n.size, 16), 8, 96);
      doc.notes.push(note);
    });

    return doc;
  };

  function num(v, fallback) {
    var n = Number(v);
    return isFinite(n) ? n : fallback;
  }
  function str(v, fallback) {
    return typeof v === 'string' ? v : fallback;
  }
  function clamp(v, lo, hi) {
    return Math.min(hi, Math.max(lo, v));
  }
  SM.clamp = clamp;

  /* --------------------------------------------------------------- checks */

  /* Authoring mistakes that would show up as a broken quest in game. Cheap
     enough to recompute on every edit. */
  SM.issues = function () {
    var out = [];
    var doc = SM.doc;

    doc.events.forEach(function (ev) {
      if (!ev.title.trim()) {
        out.push(mk('event', ev.id, 'Event has no title', true));
      }
      if (!ev.description.trim()) {
        out.push(mk('event', ev.id, title(ev) + ': no description'));
      }
      ev.options.forEach(function (op, i) {
        if (!op.label.trim()) {
          out.push(mk('event', ev.id, title(ev) + ': option ' + (i + 1) + ' has no label', true));
        } else if (!op.outcome.trim() && !op.leads_to) {
          out.push(mk('event', ev.id, title(ev) + ': "' + op.label + '" has no outcome'));
        }
      });
      var ids = {};
      allLines(ev).forEach(function (line) {
        if (line.clip_id && ids[line.clip_id]) {
          out.push(mk('event', ev.id, title(ev) + ': clip id "' + line.clip_id + '" used twice', true));
        }
        ids[line.clip_id] = true;
        if (!line.text.trim()) {
          out.push(mk('event', ev.id, title(ev) + ': a NAVOS line has no text', true));
        }
      });
    });

    cycles().forEach(function (node) {
      out.push(mk(node.type, node.id, SM.nodeTitle(node.type, node.id) +
        ': prerequisite loop — this can never unlock', true));
    });

    return out;

    function title(ev) { return (ev && ev.title) || '(untitled)'; }
    function mk(type, id, text, bad) {
      return { type: type, id: id, text: text, bad: !!bad };
    }
  };

  function allLines(ev) {
    return ev.navos.approach.concat(ev.navos.inside, ev.navos.depart);
  }

  /* Depth-first search over required links only — an optional link is a
     reference, not a gate, so it cannot deadlock anything. Keys are typed
     because an area and an event could in principle share an id. */
  function cycles() {
    var state = {};
    var bad = [];
    var out = {};
    SM.doc.links.forEach(function (l) {
      if (!l.required) { return; }
      var a = key(l.from_type || 'event', l.from);
      (out[a] = out[a] || []).push(key(l.to_type || 'event', l.to));
    });
    SM.doc.events.forEach(function (ev) { visit(key('event', ev.id)); });
    SM.doc.areas.forEach(function (a) { visit(key('area', a.id)); });
    return bad;

    function key(type, id) { return type + ':' + id; }

    function visit(k) {
      if (state[k] === 2) { return false; }
      if (state[k] === 1) {
        var split = k.indexOf(':');
        bad.push({ type: k.slice(0, split), id: k.slice(split + 1) });
        return true;
      }
      state[k] = 1;
      (out[k] || []).forEach(visit);
      state[k] = 2;
      return false;
    }
  }

})(window.SM);
