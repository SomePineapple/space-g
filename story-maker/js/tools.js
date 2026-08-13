/* tools.js — pointer interaction: select/move, event placement, linking,
 * the pen tool and notes. Panning is always available on middle-drag or with
 * space held, so no tool ever traps the canvas. */

(function (SM) {
  'use strict';

  var V = SM.view;

  SM.tool = 'select';
  SM.pen = { points: [], cursor: null };
  SM.linking = { from: null, from_type: 'event' };

  var canvas = null;
  var drag = null;
  var spaceHeld = false;
  var suppressClick = false;

  var HINTS = {
    select: 'Drag to move. Click empty space to pan. Del removes the selection.',
    event:  'Click to drop an event.',
    link:   'Click what comes first, then what it leads to. Events and areas can both be either end.',
    pen:    'Click to add corners, or drag to draw freehand. Enter closes, Esc cancels, Backspace undoes a point.',
    note:   'Click to place a note.'
  };

  SM.setTool = function (name) {
    if (SM.tool === 'pen' && name !== 'pen') { cancelPen(); }
    if (name !== 'link') { SM.linking.from = null; }
    SM.tool = name;
    canvas.className = name === 'select' ? 'select' : '';
    SM.bus.emit('tool');
    V.draw();
  };

  SM.toolHint = function () { return HINTS[SM.tool] || ''; };

  SM.attachTools = function (el) {
    canvas = el;
    canvas.addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    canvas.addEventListener('wheel', onWheel, { passive: false });
    canvas.addEventListener('dblclick', onDoubleClick);
    canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
  };

  function mouseWorld(e) {
    var r = canvas.getBoundingClientRect();
    return V.toWorld(e.clientX - r.left, e.clientY - r.top);
  }

  function isTyping(e) {
    var t = e.target;
    return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' ||
                 t.tagName === 'SELECT' || t.isContentEditable);
  }

  /* ------------------------------------------------------------ mouse down */

  function onDown(e) {
    var w = mouseWorld(e);

    if (e.button === 1 || spaceHeld || (e.button === 0 && e.altKey)) {
      drag = { mode: 'pan', lastX: e.clientX, lastY: e.clientY };
      canvas.classList.add('grabbing');
      e.preventDefault();
      return;
    }
    if (e.button !== 0) { return; }

    if (SM.tool === 'pen') { penDown(w, e); return; }

    if (SM.tool === 'event') {
      SM.push();
      var ev = SM.newEvent(w.x, w.y);
      SM.doc.events.push(ev);
      SM.select('event', ev.id);
      SM.changed();
      SM.setTool('select');
      return;
    }

    if (SM.tool === 'note') {
      SM.push();
      var note = SM.newNote(w.x, w.y);
      SM.doc.notes.push(note);
      SM.select('note', note.id);
      SM.changed();
      SM.setTool('select');
      return;
    }

    if (SM.tool === 'link') {
      /* Either end may be an event or a pen area. Events win a contested
         click because their node is the smaller target. */
      var hitEv = V.hitEvent(w.x, w.y);
      var target = hitEv || V.hitArea(w.x, w.y);
      var targetType = hitEv ? 'event' : 'area';
      if (!target) { SM.linking.from = null; V.draw(); return; }
      if (!SM.linking.from) {
        SM.linking.from = target.id;
        SM.linking.from_type = targetType;
        V.draw();
        return;
      }
      if (SM.linking.from === target.id) {
        SM.linking.from = null;
        V.draw();
        return;
      }
      SM.push();
      var link = SM.newLink(SM.linking.from, target.id,
                            SM.linking.from_type, targetType);
      SM.doc.links.push(link);
      SM.linking.from = null;
      SM.select('link', link.id);
      SM.changed();
      return;
    }

    /* -------- select tool -------- */

    var sel = SM.selected();
    if (sel && SM.sel.type === 'area') {
      var vi = V.hitAreaVertex(sel, w.x, w.y);
      if (vi >= 0) {
        SM.push();
        drag = { mode: 'vertex', area: sel, index: vi, moved: false };
        return;
      }
    }

    var note2 = V.hitNote(w.x, w.y);
    if (note2) {
      SM.select('note', note2.id);
      SM.push();
      drag = { mode: 'move', kind: 'note', obj: note2, ox: note2.x - w.x, oy: note2.y - w.y, moved: false };
      return;
    }

    var ev2 = V.hitEvent(w.x, w.y);
    if (ev2) {
      SM.select('event', ev2.id);
      SM.push();
      drag = { mode: 'move', kind: 'event', obj: ev2, ox: ev2.x - w.x, oy: ev2.y - w.y, moved: false };
      return;
    }

    var link2 = V.hitLink(w.x, w.y);
    if (link2) { SM.select('link', link2.id); return; }

    var area2 = V.hitArea(w.x, w.y);
    if (area2) {
      SM.select('area', area2.id);
      SM.push();
      drag = { mode: 'area', area: area2, lastX: w.x, lastY: w.y, moved: false };
      return;
    }

    SM.select(null);
    drag = { mode: 'pan', lastX: e.clientX, lastY: e.clientY };
    canvas.classList.add('grabbing');
  }

  /* ------------------------------------------------------------ mouse move */

  function onMove(e) {
    if (SM.tool === 'pen' && SM.pen.points.length) {
      SM.pen.cursor = [mouseWorld(e).x, mouseWorld(e).y];
      V.draw();
    }

    if (!drag) {
      var w0 = mouseWorld(e);
      SM.bus.emit('cursor', w0);
      return;
    }

    var w = mouseWorld(e);

    if (drag.mode === 'pan') {
      V.pan(e.clientX - drag.lastX, e.clientY - drag.lastY);
      drag.lastX = e.clientX;
      drag.lastY = e.clientY;
      return;
    }
    if (drag.mode === 'pen-free') {
      addFreehandPoint(w);
      return;
    }
    if (drag.mode === 'move') {
      drag.obj.x = Math.round(w.x + drag.ox);
      drag.obj.y = Math.round(w.y + drag.oy);
      drag.moved = true;
      V.draw();
      SM.bus.emit('moved');
      return;
    }
    if (drag.mode === 'vertex') {
      drag.area.points[drag.index] = [Math.round(w.x), Math.round(w.y)];
      drag.moved = true;
      V.draw();
      return;
    }
    if (drag.mode === 'area') {
      var dx = w.x - drag.lastX, dy = w.y - drag.lastY;
      drag.area.points = drag.area.points.map(function (p) {
        return [Math.round(p[0] + dx), Math.round(p[1] + dy)];
      });
      drag.lastX = w.x;
      drag.lastY = w.y;
      drag.moved = true;
      V.draw();
    }
  }

  function onUp() {
    if (drag && drag.mode === 'pen-free') {
      /* Only swallow the next click if this was a real freehand stroke — a
         plain click must be free to place the following corner. */
      suppressClick = !!drag.freehand;
      drag = null;
      return;
    }
    if (drag && drag.moved) { SM.changed(); }
    canvas.classList.remove('grabbing');
    drag = null;
  }

  function onWheel(e) {
    e.preventDefault();
    var r = canvas.getBoundingClientRect();
    var factor = Math.pow(1.0016, -e.deltaY);
    V.zoomAt(e.clientX - r.left, e.clientY - r.top, factor);
    SM.bus.emit('zoom');
  }

  function onDoubleClick(e) {
    if (SM.tool === 'pen') { finishPen(true); return; }
    var w = mouseWorld(e);
    var ev = V.hitEvent(w.x, w.y);
    if (ev) { SM.select('event', ev.id); }
  }

  /* -------------------------------------------------------------- pen tool */

  function penDown(w, e) {
    if (suppressClick) { suppressClick = false; return; }

    /* Clicking the first point again closes the shape. */
    if (SM.pen.points.length > 2) {
      var first = SM.pen.points[0];
      var s0 = V.toScreen(first[0], first[1]);
      var sc = V.toScreen(w.x, w.y);
      if (Math.hypot(s0.x - sc.x, s0.y - sc.y) < 9) { finishPen(true); return; }
    }
    SM.pen.points.push([Math.round(w.x), Math.round(w.y)]);
    drag = { mode: 'pen-free', last: [w.x, w.y] };
    V.draw();
  }

  /* Freehand sampling is in screen space so the stroke density does not change
     with zoom. */
  function addFreehandPoint(w) {
    var pts = SM.pen.points;
    var last = pts[pts.length - 1];
    var a = V.toScreen(last[0], last[1]);
    var b = V.toScreen(w.x, w.y);
    if (Math.hypot(a.x - b.x, a.y - b.y) < 7) { return; }
    pts.push([Math.round(w.x), Math.round(w.y)]);
    if (drag) { drag.freehand = true; }
    V.draw();
  }

  function finishPen(closed) {
    if (SM.pen.points.length < 2) { cancelPen(); return; }
    SM.push();
    var area = SM.newArea(SM.pen.points.slice());
    area.closed = !!closed && area.points.length > 2;
    SM.doc.areas.push(area);
    SM.pen.points = [];
    SM.pen.cursor = null;
    SM.select('area', area.id);
    SM.changed();
    SM.setTool('select');
  }

  function cancelPen() {
    SM.pen.points = [];
    SM.pen.cursor = null;
    V.draw();
  }

  /* ------------------------------------------------------------- keyboard */

  function onKeyDown(e) {
    if (e.code === 'Space' && !isTyping(e)) {
      spaceHeld = true;
      e.preventDefault();
    }
    if (isTyping(e)) {
      if (e.key === 'Escape') { e.target.blur(); }
      return;
    }

    var meta = e.ctrlKey || e.metaKey;

    if (meta && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) { SM.redo(); } else { SM.undo(); }
      return;
    }
    if (meta && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      SM.redo();
      return;
    }
    if (meta && e.key.toLowerCase() === 's') {
      e.preventDefault();
      SM.storage.save();
      return;
    }
    if (meta) { return; }

    switch (e.key) {
      case 'Escape':
        if (SM.tool === 'pen') { cancelPen(); SM.setTool('select'); }
        else if (SM.linking.from) { SM.linking.from = null; V.draw(); }
        else { SM.select(null); }
        return;
      case 'Enter':
        if (SM.tool === 'pen') { finishPen(true); }
        return;
      case 'Backspace':
        if (SM.tool === 'pen' && SM.pen.points.length) {
          SM.pen.points.pop();
          V.draw();
          return;
        }
        deleteSelection();
        return;
      case 'Delete':
        deleteSelection();
        return;
      case 'v': case 'V': SM.setTool('select'); return;
      case 'e': case 'E': SM.setTool('event'); return;
      case 'l': case 'L': SM.setTool('link'); return;
      case 'p': case 'P': SM.setTool('pen'); return;
      case 'n': case 'N': SM.setTool('note'); return;
      case 'f': case 'F': V.fit(); SM.bus.emit('zoom'); return;
      default: return;
    }
  }

  function onKeyUp(e) {
    if (e.code === 'Space') { spaceHeld = false; }
  }

  function deleteSelection() {
    if (!SM.sel) { return; }
    /* Deleting either kind of link endpoint silently takes its links with it,
       so both are worth confirming. */
    var linked = SM.sel.type === 'event' ||
                 (SM.sel.type === 'area' &&
                  (SM.linksInto('area', SM.sel.id).length ||
                   SM.linksOutOf('area', SM.sel.id).length));
    var label = linked
      ? 'Delete "' + SM.nodeTitle(SM.sel.type, SM.sel.id) + '" and its links?'
      : null;
    if (label && !window.confirm(label)) { return; }
    SM.push();
    SM.deleteObject(SM.sel.type, SM.sel.id);
    SM.select(null);
    SM.changed();
  }
  SM.deleteSelection = deleteSelection;

})(window.SM);
