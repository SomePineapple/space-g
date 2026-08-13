/* inspector.js — the right-hand editing panel.
 *
 * Deliberately re-rendered only on selection changes and structural edits, not
 * on every keystroke: rebuilding the DOM mid-typing would steal focus. Text
 * fields write straight into the model and let the canvas redraw itself. */

(function (SM) {
  'use strict';

  var root = null;
  var liveRefs = {};        /* inputs kept in sync while dragging on canvas */

  SM.inspector = {};

  SM.inspector.attach = function (el) {
    root = el;
    SM.bus.on('selection', render);
    SM.bus.on('doc', render);
    SM.bus.on('moved', syncPosition);
    render();
  };

  SM.inspector.render = render;

  /* --------------------------------------------------------- dom helpers */

  function el(tag, attrs, kids) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'class') { node.className = attrs[k]; }
      else if (k === 'text') { node.textContent = attrs[k]; }
      else if (k === 'html') { node.innerHTML = attrs[k]; }
      else if (k.slice(0, 2) === 'on') { node.addEventListener(k.slice(2), attrs[k]); }
      else if (attrs[k] !== null && attrs[k] !== undefined) { node.setAttribute(k, attrs[k]); }
    });
    (kids || []).forEach(function (kid) {
      if (kid) { node.appendChild(kid); }
    });
    return node;
  }

  function field(label, input) {
    return el('label', { class: 'field' }, [el('span', { text: label }), input]);
  }

  function commit(key, fn) {
    return function (e) {
      SM.push(key);
      fn(e.target.value);
      SM.changed();
    };
  }

  function textBox(value, key, set, placeholder) {
    var i = el('input', { type: 'text', value: value || '', spellcheck: 'false' });
    if (placeholder) { i.placeholder = placeholder; }
    i.addEventListener('input', commit(key, set));
    return i;
  }

  function textArea(value, key, set, rows, placeholder) {
    var t = el('textarea', { rows: rows || 3 });
    t.value = value || '';
    if (placeholder) { t.placeholder = placeholder; }
    t.addEventListener('input', commit(key, set));
    return t;
  }

  function numberBox(value, key, set, step) {
    var i = el('input', { type: 'number', value: value, step: step || 1 });
    i.addEventListener('input', commit(key, function (v) { set(Number(v) || 0); }));
    return i;
  }

  function colorBox(value, key, set, fallback) {
    var i = el('input', { type: 'color', value: value || fallback || '#35d0e0' });
    i.addEventListener('input', commit(key, set));
    return i;
  }

  function selectBox(values, value, key, set, labels) {
    var s = el('select', {});
    values.forEach(function (v, i) {
      var o = el('option', { value: v, text: labels ? labels[i] : v });
      if (v === value) { o.selected = true; }
      s.appendChild(o);
    });
    s.addEventListener('change', commit(key, set));
    return s;
  }

  function checkRow(label, checked, set) {
    var input = el('input', { type: 'checkbox' });
    input.checked = !!checked;
    input.addEventListener('change', function () {
      SM.push();
      set(input.checked);
      SM.changed();
      render();
    });
    return el('label', { class: 'check' }, [input, el('span', { text: label })]);
  }

  function block(title, kids, headButton) {
    var h = el('h3', { text: title }, headButton ? [headButton] : []);
    return el('div', { class: 'block' }, [h].concat(kids));
  }

  function button(label, onClick, cls) {
    return el('button', { class: cls || '', text: label, onclick: onClick });
  }

  /* -------------------------------------------------------------- render */

  function render() {
    if (!root) { return; }
    liveRefs = {};
    root.innerHTML = '';
    var obj = SM.selected();

    if (!obj) { root.appendChild(mapSettings()); return; }
    if (SM.sel.type === 'event') { root.appendChild(eventForm(obj)); return; }
    if (SM.sel.type === 'link') { root.appendChild(linkForm(obj)); return; }
    if (SM.sel.type === 'area') { root.appendChild(areaForm(obj)); return; }
    if (SM.sel.type === 'note') { root.appendChild(noteForm(obj)); return; }
  }

  function syncPosition() {
    if (liveRefs.x) { liveRefs.x.value = SM.selected() ? SM.selected().x : ''; }
    if (liveRefs.y) { liveRefs.y.value = SM.selected() ? SM.selected().y : ''; }
  }

  function head(title, id, onDelete) {
    var kids = [el('h2', { text: title })];
    if (id) { kids.push(el('span', { class: 'id', text: id })); }
    if (onDelete) { kids.push(button('Delete', onDelete, 'danger')); }
    return el('div', { class: 'insp-head' }, kids);
  }

  /* -------------------------------------------------------- map settings */

  function mapSettings() {
    var d = SM.doc;
    var wrap = el('div', {}, [head('Map', null, null)]);

    wrap.appendChild(el('p', {
      class: 'note-text',
      text: 'Nothing selected. Click an event, link, area or note to edit it.'
    }));

    wrap.appendChild(block('Canvas', [
      field('Grid spacing (units)', numberBox(d.map.grid, 'grid', function (v) {
        d.map.grid = Math.max(10, v);
      }, 10)),
      el('div', { class: 'field-row' }, [
        field('Events', el('input', { type: 'text', value: d.events.length, disabled: 'disabled' })),
        field('Links', el('input', { type: 'text', value: d.links.length, disabled: 'disabled' })),
        field('Areas', el('input', { type: 'text', value: d.areas.length, disabled: 'disabled' }))
      ])
    ]));

    var bg = d.map.background;
    var bgKids = [];
    if (bg) {
      bgKids.push(el('p', { class: 'note-text', text: bg.name || 'image' }));
      bgKids.push(el('div', { class: 'field-row' }, [
        field('X', numberBox(bg.x, 'bgx', function (v) { bg.x = v; }, 10)),
        field('Y', numberBox(bg.y, 'bgy', function (v) { bg.y = v; }, 10))
      ]));
      bgKids.push(el('div', { class: 'field-row' }, [
        field('Width', numberBox(bg.w, 'bgw', function (v) { bg.w = Math.max(1, v); }, 10)),
        field('Height', numberBox(bg.h, 'bgh', function (v) { bg.h = Math.max(1, v); }, 10))
      ]));
      bgKids.push(field('Opacity', numberBox(bg.opacity, 'bgo', function (v) {
        bg.opacity = SM.clamp(v, 0, 1);
      }, 0.05)));
      bgKids.push(button('Remove image', function () {
        SM.push();
        d.map.background = null;
        SM.changed();
        render();
      }, 'danger'));
    } else {
      bgKids.push(el('p', {
        class: 'note-text',
        text: 'Optional reference image drawn under the map. Stored inside the map file, so keep it small.'
      }));
      bgKids.push(button('Load image…', function () {
        document.getElementById('image-input').click();
      }));
    }
    wrap.appendChild(block('Background', bgKids));

    return wrap;
  }

  /* --------------------------------------------------------- event form */

  function eventForm(ev) {
    var wrap = el('div', {}, [head('Event', ev.id, function () {
      SM.select('event', ev.id);
      SM.deleteSelection();
    })]);

    wrap.appendChild(field('Title', textBox(ev.title, 'title' + ev.id, function (v) {
      ev.title = v;
    })));

    var typeInput = textBox(ev.type, 'type' + ev.id, function (v) { ev.type = v; });
    typeInput.setAttribute('list', 'event-types');
    wrap.appendChild(field('Type', typeInput));
    wrap.appendChild(typeDatalist());

    var xIn = numberBox(ev.x, 'x' + ev.id, function (v) { ev.x = v; }, 10);
    var yIn = numberBox(ev.y, 'y' + ev.id, function (v) { ev.y = v; }, 10);
    liveRefs.x = xIn;
    liveRefs.y = yIn;
    wrap.appendChild(el('div', { class: 'field-row' }, [
      field('X', xIn), field('Y', yIn)
    ]));

    wrap.appendChild(el('div', { class: 'field-row' }, [
      field('Trigger radius', numberBox(ev.radius, 'r' + ev.id, function (v) {
        ev.radius = Math.max(0, v);
      }, 25)),
      field('Colour', colorBox(ev.color || SM.eventColor(ev), 'c' + ev.id, function (v) {
        ev.color = v;
      }))
    ]));

    wrap.appendChild(checkRow('Fires once only', ev.once, function (v) { ev.once = v; }));

    wrap.appendChild(field('Description (shown to the player)',
      textArea(ev.description, 'desc' + ev.id, function (v) { ev.description = v; }, 5)));

    wrap.appendChild(field('Tags (comma separated)',
      textBox(ev.tags.join(', '), 'tags' + ev.id, function (v) {
        ev.tags = v.split(',').map(function (s) { return s.trim(); })
                   .filter(function (s) { return s; });
      })));

    wrap.appendChild(optionsBlock(ev));
    wrap.appendChild(navosBlock(ev));
    wrap.appendChild(logBlock(ev));
    wrap.appendChild(prereqBlock(ev));
    wrap.appendChild(linksBlock('event', ev.id, false));

    wrap.appendChild(block('Author notes', [
      el('p', { class: 'note-text', text: 'Never shown in game.' }),
      textArea(ev.notes, 'notes' + ev.id, function (v) { ev.notes = v; }, 3)
    ]));

    return wrap;
  }

  function typeDatalist() {
    var dl = el('datalist', { id: 'event-types' });
    var seen = {};
    SM.EVENT_TYPES.forEach(function (t) { seen[t] = true; });
    SM.doc.events.forEach(function (e) { if (e.type) { seen[e.type] = true; } });
    Object.keys(seen).forEach(function (t) {
      dl.appendChild(el('option', { value: t }));
    });
    return dl;
  }

  function optionsBlock(ev) {
    var add = button('+ Option', function () {
      SM.push();
      ev.options.push(SM.newOption());
      SM.changed();
      render();
    });
    add.disabled = ev.options.length >= 3;

    var kids = [];
    if (!ev.options.length) {
      kids.push(el('p', {
        class: 'empty',
        text: 'No choices — the player just reads the description.'
      }));
    }

    ev.options.forEach(function (op, i) {
      var sub = el('div', { class: 'sub' });
      sub.appendChild(el('div', { class: 'sub-head' }, [
        el('span', { text: 'Option ' + (i + 1) }),
        el('button', {
          class: 'x', text: '×', title: 'Remove this option',
          onclick: function () {
            SM.push();
            ev.options.splice(i, 1);
            SM.changed();
            render();
          }
        })
      ]));
      sub.appendChild(field('Button label', textBox(op.label, 'ol' + op.id, function (v) {
        op.label = v;
      }, 'Answer the signal')));
      sub.appendChild(field('Outcome text', textArea(op.outcome, 'oo' + op.id, function (v) {
        op.outcome = v;
      }, 3)));
      sub.appendChild(field('NAVOS line on this choice',
        textArea(op.navos.text, 'on' + op.id, function (v) { op.navos.text = v; }, 2)));
      sub.appendChild(field('NAVOS clip id',
        textBox(op.navos.clip_id, 'oc' + op.id, function (v) {
          op.navos.clip_id = v;
        }, 'e.g. Distress_03')));
      sub.appendChild(field('Captain\'s log line for this choice',
        textArea(op.log_text, 'og' + op.id, function (v) { op.log_text = v; }, 2)));

      var targets = [''].concat(SM.doc.events
        .filter(function (e) { return e.id !== ev.id; })
        .map(function (e) { return e.id; }));
      var labels = ['(nothing)'].concat(targets.slice(1).map(SM.eventTitle));
      var sel = selectBox(targets, op.leads_to, null, function (v) {
        op.leads_to = v;
        if (v) { SM.ensureChoiceLink(ev.id, v, op.label); }
        SM.inspector.render();
      }, labels);
      sub.appendChild(field('Leads to', sel));

      kids.push(sub);
    });

    return block('Player choices (' + ev.options.length + '/3)', kids, add);
  }

  var NAVOS_SLOTS = [
    ['approach', 'On approach'],
    ['inside', 'While inside'],
    ['depart', 'On leaving']
  ];

  function navosBlock(ev) {
    var kids = [el('p', {
      class: 'note-text',
      text: 'Clip id matches the wav name used by CoreVoiceLines; the text is the subtitle.'
    })];

    NAVOS_SLOTS.forEach(function (slot) {
      var key = slot[0];
      var lines = ev.navos[key];
      var sub = el('div', { class: 'sub' });
      sub.appendChild(el('div', { class: 'sub-head' }, [
        el('span', { text: slot[1] + ' (' + lines.length + ')' }),
        el('button', {
          class: 'x', text: '+', title: 'Add a line',
          onclick: function () {
            SM.push();
            lines.push(SM.newNavosLine());
            SM.changed();
            render();
          }
        })
      ]));

      if (!lines.length) {
        sub.appendChild(el('p', { class: 'empty', text: 'No lines.' }));
      }

      lines.forEach(function (line, i) {
        var row = el('div', { class: 'field-row' }, [
          field('Clip id', textBox(line.clip_id, 'vc' + line.id, function (v) {
            line.clip_id = v;
          }, 'Optional')),
          el('label', { class: 'field' }, [
            el('span', { text: ' ' }),
            el('button', {
              text: 'Remove', class: 'danger',
              onclick: function () {
                SM.push();
                lines.splice(i, 1);
                SM.changed();
                render();
              }
            })
          ])
        ]);
        sub.appendChild(row);
        sub.appendChild(field('Line ' + (i + 1),
          textArea(line.text, 'vt' + line.id, function (v) { line.text = v; }, 2)));
      });

      kids.push(sub);
    });

    return block('NAVOS', kids);
  }

  function logBlock(ev) {
    return block('Captain\'s log', [
      el('p', { class: 'note-text', text: 'Written to the log when this event resolves.' }),
      field('Entry title', textBox(ev.log.title, 'lt' + ev.id, function (v) {
        ev.log.title = v;
      })),
      field('Entry text', textArea(ev.log.text, 'lx' + ev.id, function (v) {
        ev.log.text = v;
      }, 4))
    ]);
  }

  function prereqBlock(ev) {
    var incoming = SM.linksInto('event', ev.id);
    var kids = [];

    kids.push(field('When several are required',
      selectBox(['all', 'any'], ev.prereq_mode, null, function (v) {
        ev.prereq_mode = v;
        SM.changed();
      }, ['All must have happened', 'Any one is enough'])));

    if (!incoming.length) {
      kids.push(el('p', { class: 'empty', text: 'Nothing leads here — this event can fire from the start.' }));
    }

    incoming.forEach(function (link) {
      var fromType = link.from_type || 'event';
      var sub = el('div', { class: 'sub' });
      sub.appendChild(el('div', { class: 'sub-head' }, [
        el('span', { text: endpointLabel(fromType, link.from) }),
        el('button', {
          class: 'x', text: 'Edit', title: 'Select this link',
          onclick: function () { SM.select('link', link.id); }
        })
      ]));
      sub.appendChild(checkRow(fromType === 'area'
        ? 'Player must have entered this area first'
        : 'Must happen before this event', link.required, function (v) {
        link.required = v;
      }));
      kids.push(sub);
    });

    return block('Prerequisites', kids);
  }

  /* Shared by events and areas. Events list only their outgoing links here,
     because their incoming ones are the Prerequisites block above. */
  function linksBlock(type, id, includeIncoming) {
    var outgoing = SM.linksOutOf(type, id);
    var incoming = includeIncoming ? SM.linksInto(type, id) : [];
    var kids = [];

    if (!outgoing.length && !incoming.length) {
      kids.push(el('p', { class: 'empty', text: 'No links yet.' }));
    }
    outgoing.forEach(function (link) {
      kids.push(linkRow('→', link.to_type || 'event', link.to, link));
    });
    incoming.forEach(function (link) {
      kids.push(linkRow('←', link.from_type || 'event', link.from, link));
    });

    /* A picker as well as the L tool: an area's anchor can be an awkward
       click when shapes overlap. */
    var picker = el('select', {});
    picker.appendChild(el('option', { value: '', text: 'Link this to…' }));
    SM.doc.events.forEach(function (e) {
      if (type === 'event' && e.id === id) { return; }
      picker.appendChild(el('option', {
        value: 'event:' + e.id, text: '● ' + (e.title || '(untitled)')
      }));
    });
    SM.doc.areas.forEach(function (a) {
      if (type === 'area' && a.id === id) { return; }
      picker.appendChild(el('option', {
        value: 'area:' + a.id, text: '▱ ' + (a.name || '(unnamed area)')
      }));
    });
    picker.addEventListener('change', function () {
      if (!picker.value) { return; }
      var split = picker.value.indexOf(':');
      SM.push();
      SM.doc.links.push(SM.newLink(id, picker.value.slice(split + 1),
                                   type, picker.value.slice(0, split)));
      SM.changed();
      render();
    });
    kids.push(picker);

    return block('Links', kids);
  }

  function linkRow(arrow, otherType, otherId, link) {
    return el('div', { class: 'sub-head' }, [
      el('span', {
        text: arrow + ' ' + endpointLabel(otherType, otherId) +
              (link.required ? '  (required)' : '')
      }),
      el('button', {
        class: 'x', text: 'Edit', title: 'Select this link',
        onclick: function () { SM.select('link', link.id); }
      }),
      el('button', {
        class: 'x', text: '×', title: 'Remove this link',
        onclick: function () {
          SM.push();
          SM.deleteObject('link', link.id);
          SM.changed();
          render();
        }
      })
    ]);
  }

  /* ---------------------------------------------------------- link form */

  function linkForm(link) {
    var wrap = el('div', {}, [head('Link', link.id, function () {
      SM.push();
      SM.deleteObject('link', link.id);
      SM.select(null);
      SM.changed();
    })]);

    var fromType = link.from_type || 'event';
    var toType = link.to_type || 'event';

    wrap.appendChild(el('p', {
      class: 'note-text',
      text: endpointLabel(fromType, link.from) + '  →  ' + endpointLabel(toType, link.to)
    }));

    wrap.appendChild(button('Swap direction', function () {
      SM.push();
      var id = link.from, type = fromType;
      link.from = link.to;
      link.from_type = toType;
      link.to = id;
      link.to_type = type;
      if (link.to_type === 'area') { link.required = false; }
      SM.changed();
      render();
    }));

    /* An area is a place, not something that completes, so it can only ever be
       the source of a prerequisite — "the player must have been here first". */
    var gate = toType === 'area'
      ? el('p', {
          class: 'empty',
          text: 'An area cannot be gated — it has nothing to complete. This link is a board reference.'
        })
      : checkRow(fromType === 'area'
          ? 'Player must have entered this area first'
          : 'Source must happen before target', link.required, function (v) {
        link.required = v;
      });

    wrap.appendChild(block('Behaviour', [
      gate,
      field('Kind', selectBox(SM.LINK_KINDS, link.kind, null, function (v) {
        link.kind = v;
        SM.changed();
      }, ['Sequence', 'Player choice', 'Reference only'])),
      field('Label on the board', textBox(link.label, 'll' + link.id, function (v) {
        link.label = v;
      })),
      field('Colour', colorBox(link.color || '#35d0e0', 'lc' + link.id, function (v) {
        link.color = v;
      }))
    ]));

    wrap.appendChild(el('div', { class: 'btn-row' }, [
      button('Go to source', function () { focusNode(fromType, link.from); }),
      button('Go to target', function () { focusNode(toType, link.to); })
    ]));

    return wrap;
  }

  function endpointLabel(type, id) {
    return (type === 'area' ? '▱ ' : '● ') + SM.nodeTitle(type, id);
  }

  function focusNode(type, id) {
    var anchor = SM.nodeAnchor(type, id);
    if (!anchor) { return; }
    SM.select(type, id);
    SM.view.centreOn(anchor.x, anchor.y);
  }
  SM.inspector.focusNode = focusNode;
  SM.inspector.focusEvent = function (id) { focusNode('event', id); };

  /* ---------------------------------------------------------- area form */

  function areaForm(area) {
    var wrap = el('div', {}, [head('Area', area.id, function () {
      SM.push();
      SM.deleteObject('area', area.id);
      SM.select(null);
      SM.changed();
    })]);

    wrap.appendChild(field('Name', textBox(area.name, 'an' + area.id, function (v) {
      area.name = v;
    })));

    wrap.appendChild(el('div', { class: 'field-row' }, [
      field('Fill', colorBox(area.fill, 'af' + area.id, function (v) { area.fill = v; })),
      field('Stroke', colorBox(area.stroke, 'as' + area.id, function (v) { area.stroke = v; })),
      field('Opacity', numberBox(area.opacity, 'ao' + area.id, function (v) {
        area.opacity = SM.clamp(v, 0, 1);
      }, 0.05))
    ]));

    wrap.appendChild(checkRow('Closed shape', area.closed, function (v) { area.closed = v; }));

    wrap.appendChild(field('Notation', textArea(area.note, 'at' + area.id, function (v) {
      area.note = v;
    }, 3)));

    wrap.appendChild(linksBlock('area', area.id, true));

    wrap.appendChild(el('p', {
      class: 'note-text',
      text: area.points.length + ' points. Drag a handle to reshape, drag the body ' +
            'to move it. Links attach to the diamond at its centre.'
    }));

    return wrap;
  }

  /* ---------------------------------------------------------- note form */

  function noteForm(note) {
    var wrap = el('div', {}, [head('Note', note.id, function () {
      SM.push();
      SM.deleteObject('note', note.id);
      SM.select(null);
      SM.changed();
    })]);

    wrap.appendChild(field('Text', textArea(note.text, 'nt' + note.id, function (v) {
      note.text = v;
    }, 3)));

    var xIn = numberBox(note.x, 'nx' + note.id, function (v) { note.x = v; }, 10);
    var yIn = numberBox(note.y, 'ny' + note.id, function (v) { note.y = v; }, 10);
    liveRefs.x = xIn;
    liveRefs.y = yIn;

    wrap.appendChild(el('div', { class: 'field-row' }, [
      field('X', xIn), field('Y', yIn)
    ]));
    wrap.appendChild(el('div', { class: 'field-row' }, [
      field('Size', numberBox(note.size, 'ns' + note.id, function (v) {
        note.size = SM.clamp(v, 8, 96);
      }, 1)),
      field('Colour', colorBox(note.color, 'nc' + note.id, function (v) { note.color = v; }))
    ]));

    return wrap;
  }

})(window.SM);
