/* view.js — camera, hit testing and all canvas drawing.
 *
 * World units are the map's own abstract space (see README). The camera is
 * screen = world * zoom + (view.x, view.y), stored on the document so a map
 * reopens where it was left. Event nodes are drawn at a fixed *screen* size so
 * they stay clickable at any zoom; trigger radii, areas and notes scale with
 * the world, because those are real distances the author is judging. */

(function (SM) {
  'use strict';

  var V = {};
  SM.view = V;

  var canvas = null;
  var ctx = null;
  var dpr = 1;

  V.NODE_R = 13;          /* screen px */
  V.ANCHOR_R = 7;         /* an area's link anchor, screen px */
  V.MIN_ZOOM = 0.02;
  V.MAX_ZOOM = 8;

  V.attach = function (el) {
    canvas = el;
    ctx = canvas.getContext('2d');
    V.resize();
    /* Anything that changes the canvas box — window resize, browser zoom,
       devtools, a panel growing — has to update the cached size, or every
       screen/world conversion silently drifts. */
    if (window.ResizeObserver) {
      new window.ResizeObserver(function () { V.resize(); }).observe(canvas);
    }
  };

  V.resize = function () {
    if (!canvas) { return; }
    var nextDpr = window.devicePixelRatio || 1;
    var r = canvas.getBoundingClientRect();
    if (r.width === V.width && r.height === V.height && nextDpr === dpr) {
      return;                        /* nothing moved — and no observer loop */
    }
    dpr = nextDpr;
    canvas.width = Math.max(1, Math.round(r.width * dpr));
    canvas.height = Math.max(1, Math.round(r.height * dpr));
    V.width = r.width;
    V.height = r.height;
    V.draw();
  };

  function cam() { return SM.doc.map.view; }

  V.toScreen = function (x, y) {
    var c = cam();
    return { x: x * c.zoom + c.x, y: y * c.zoom + c.y };
  };

  V.toWorld = function (sx, sy) {
    var c = cam();
    return { x: (sx - c.x) / c.zoom, y: (sy - c.y) / c.zoom };
  };

  V.zoomAt = function (sx, sy, factor) {
    var c = cam();
    var before = V.toWorld(sx, sy);
    c.zoom = SM.clamp(c.zoom * factor, V.MIN_ZOOM, V.MAX_ZOOM);
    var after = V.toWorld(sx, sy);
    c.x += (after.x - before.x) * c.zoom;
    c.y += (after.y - before.y) * c.zoom;
    V.draw();
  };

  V.pan = function (dx, dy) {
    var c = cam();
    c.x += dx;
    c.y += dy;
    V.draw();
  };

  V.centreOn = function (x, y) {
    var c = cam();
    c.x = V.width / 2 - x * c.zoom;
    c.y = V.height / 2 - y * c.zoom;
    V.draw();
  };

  V.resetZoom = function () {
    var c = cam();
    var mid = V.toWorld(V.width / 2, V.height / 2);
    c.zoom = 1;
    V.centreOn(mid.x, mid.y);
  };

  /* Frame everything on the map, with a margin so nothing sits on the edge. */
  V.fit = function () {
    var b = bounds();
    var c = cam();
    if (!b) {
      c.zoom = 1;
      V.centreOn(0, 0);
      return;
    }
    var pad = 90;
    var w = Math.max(b.maxX - b.minX, 1);
    var h = Math.max(b.maxY - b.minY, 1);
    c.zoom = SM.clamp(
      Math.min((V.width - pad * 2) / w, (V.height - pad * 2) / h),
      V.MIN_ZOOM, V.MAX_ZOOM
    );
    V.centreOn((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2);
  };

  function bounds() {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    var any = false;
    function add(x, y) {
      any = true;
      if (x < minX) { minX = x; }
      if (y < minY) { minY = y; }
      if (x > maxX) { maxX = x; }
      if (y > maxY) { maxY = y; }
    }
    SM.doc.events.forEach(function (e) {
      add(e.x - e.radius, e.y - e.radius);
      add(e.x + e.radius, e.y + e.radius);
    });
    SM.doc.notes.forEach(function (n) { add(n.x, n.y); });
    SM.doc.areas.forEach(function (a) {
      a.points.forEach(function (p) { add(p[0], p[1]); });
    });
    var bg = SM.doc.map.background;
    if (bg) { add(bg.x, bg.y); add(bg.x + bg.w, bg.y + bg.h); }
    return any ? { minX: minX, minY: minY, maxX: maxX, maxY: maxY } : null;
  }
  V.bounds = bounds;

  /* ------------------------------------------------------------ hit tests */

  V.hitNote = function (wx, wy) {
    var notes = SM.doc.notes;
    for (var i = notes.length - 1; i >= 0; i--) {
      var n = notes[i];
      var s = V.toScreen(n.x, n.y);
      var p = V.toScreen(wx, wy);
      var w = measure(n.text, n.size * cam().zoom);
      var h = n.size * cam().zoom + 6;
      if (p.x >= s.x - 5 && p.x <= s.x + w + 8 && p.y >= s.y - h && p.y <= s.y + 5) {
        return n;
      }
    }
    return null;
  };

  V.hitEvent = function (wx, wy) {
    var p = V.toScreen(wx, wy);
    var list = SM.doc.events;
    for (var i = list.length - 1; i >= 0; i--) {
      var s = V.toScreen(list[i].x, list[i].y);
      if (Math.hypot(p.x - s.x, p.y - s.y) <= V.NODE_R + 3) { return list[i]; }
    }
    return null;
  };

  V.hitAreaVertex = function (area, wx, wy) {
    var p = V.toScreen(wx, wy);
    for (var i = 0; i < area.points.length; i++) {
      var s = V.toScreen(area.points[i][0], area.points[i][1]);
      if (Math.hypot(p.x - s.x, p.y - s.y) <= 6) { return i; }
    }
    return -1;
  };

  V.hitArea = function (wx, wy) {
    var list = SM.doc.areas;
    var p = V.toScreen(wx, wy);
    /* The centroid anchor wins, so an area whose links you want to grab is
       reachable even when its shape is open or sits under something else. */
    for (var a = list.length - 1; a >= 0; a--) {
      var c = V.toScreen(SM.areaCentre(list[a]).x, SM.areaCentre(list[a]).y);
      if (Math.hypot(p.x - c.x, p.y - c.y) <= V.ANCHOR_R + 3) { return list[a]; }
    }
    for (var i = list.length - 1; i >= 0; i--) {
      if (pointInPoly(wx, wy, list[i].points)) { return list[i]; }
      if (nearEdge(wx, wy, list[i])) { return list[i]; }
    }
    return null;
  };

  V.hitLink = function (wx, wy) {
    var tol = 7 / cam().zoom;
    var list = SM.doc.links;
    for (var i = list.length - 1; i >= 0; i--) {
      var g = linkGeometry(list[i], i);
      if (!g) { continue; }
      for (var t = 0; t <= 1.0001; t += 0.05) {
        var pt = quad(g.a, g.c, g.b, t);
        if (Math.hypot(pt.x - wx, pt.y - wy) <= tol) { return list[i]; }
      }
    }
    return null;
  };

  function pointInPoly(x, y, pts) {
    if (pts.length < 3) { return false; }
    var inside = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      var xi = pts[i][0], yi = pts[i][1], xj = pts[j][0], yj = pts[j][1];
      if ((yi > y) !== (yj > y) &&
          x < (xj - xi) * (y - yi) / ((yj - yi) || 1e-9) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  function nearEdge(x, y, area) {
    var tol = 6 / cam().zoom;
    var pts = area.points;
    var last = area.closed ? pts.length : pts.length - 1;
    for (var i = 0; i < last; i++) {
      var a = pts[i], b = pts[(i + 1) % pts.length];
      if (distToSegment(x, y, a[0], a[1], b[0], b[1]) <= tol) { return true; }
    }
    return false;
  }

  function distToSegment(px, py, ax, ay, bx, by) {
    var dx = bx - ax, dy = by - ay;
    var len2 = dx * dx + dy * dy;
    var t = len2 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
  }

  /* --------------------------------------------------------------- layout */

  /* Links bow outward so that several links between the same pair, and the
     two directions of a mutual pair, stay separately clickable. An endpoint is
     an event's position or an area's centroid. */
  function linkGeometry(link, index) {
    var from = SM.nodeAnchor(link.from_type || 'event', link.from);
    var to = SM.nodeAnchor(link.to_type || 'event', link.to);
    if (!from || !to) { return null; }
    if (from.x === to.x && from.y === to.y) { return null; }

    var siblings = SM.doc.links.filter(function (l) {
      return (l.from === link.from && l.to === link.to) ||
             (l.from === link.to && l.to === link.from);
    });
    var slot = siblings.indexOf(link);
    var dx = to.x - from.x, dy = to.y - from.y;
    var len = Math.hypot(dx, dy) || 1;
    var bow = (slot - (siblings.length - 1) / 2) * Math.min(len * 0.22, 220);
    if (siblings.length === 1) { bow = Math.min(len * 0.08, 90); }

    var mx = (from.x + to.x) / 2, my = (from.y + to.y) / 2;
    return {
      a: { x: from.x, y: from.y },
      b: { x: to.x, y: to.y },
      c: { x: mx + (-dy / len) * bow, y: my + (dx / len) * bow }
    };
  }
  V.linkGeometry = linkGeometry;

  function quad(a, c, b, t) {
    var u = 1 - t;
    return {
      x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
      y: u * u * a.y + 2 * u * t * c.y + t * t * b.y
    };
  }

  function measure(text, px) {
    if (!ctx) { return 0; }
    ctx.font = px + 'px "Segoe UI", system-ui, sans-serif';
    return ctx.measureText(text || '').width;
  }

  /* ------------------------------------------------------------- drawing */

  var bgImage = null;
  var bgSrc = null;

  V.draw = function () {
    if (!ctx) { return; }
    var c = cam();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, V.width, V.height);
    ctx.fillStyle = '#070b10';
    ctx.fillRect(0, 0, V.width, V.height);

    drawGrid();

    ctx.save();
    ctx.translate(c.x, c.y);
    ctx.scale(c.zoom, c.zoom);

    drawBackground();
    SM.doc.areas.forEach(drawArea);
    if (SM.pen && SM.pen.points.length) { drawPenPreview(); }
    SM.doc.links.forEach(drawLink);
    SM.doc.events.forEach(drawEventRadius);

    ctx.restore();

    /* Nodes and labels are drawn unscaled so text stays crisp and hit targets
       stay constant — the transform above is only for world-space geometry. */
    SM.doc.events.forEach(drawEventNode);
    SM.doc.notes.forEach(drawNote);
    drawLinkLabels();
  };

  function drawGrid() {
    var c = cam();
    var step = SM.doc.map.grid || 250;
    while (step * c.zoom < 26) { step *= 4; }
    var x0 = V.toWorld(0, 0).x, y0 = V.toWorld(0, 0).y;
    var x1 = V.toWorld(V.width, V.height).x, y1 = V.toWorld(V.width, V.height).y;

    ctx.lineWidth = 1;
    ctx.strokeStyle = 'rgba(53, 208, 224, 0.06)';
    ctx.beginPath();
    for (var x = Math.floor(x0 / step) * step; x < x1; x += step) {
      var sx = Math.round(V.toScreen(x, 0).x) + 0.5;
      ctx.moveTo(sx, 0); ctx.lineTo(sx, V.height);
    }
    for (var y = Math.floor(y0 / step) * step; y < y1; y += step) {
      var sy = Math.round(V.toScreen(0, y).y) + 0.5;
      ctx.moveTo(0, sy); ctx.lineTo(V.width, sy);
    }
    ctx.stroke();

    /* Origin cross — the only fixed landmark in an abstract space. */
    var o = V.toScreen(0, 0);
    ctx.strokeStyle = 'rgba(53, 208, 224, 0.28)';
    ctx.beginPath();
    ctx.moveTo(o.x - 9, o.y); ctx.lineTo(o.x + 9, o.y);
    ctx.moveTo(o.x, o.y - 9); ctx.lineTo(o.x, o.y + 9);
    ctx.stroke();
  }

  function drawBackground() {
    var bg = SM.doc.map.background;
    if (!bg || !bg.src) { return; }
    if (bgSrc !== bg.src) {
      bgSrc = bg.src;
      bgImage = new Image();
      bgImage.onload = function () { V.draw(); };
      bgImage.src = bg.src;
    }
    if (bgImage && bgImage.complete && bgImage.naturalWidth) {
      ctx.save();
      ctx.globalAlpha = bg.opacity == null ? 1 : bg.opacity;
      ctx.drawImage(bgImage, bg.x, bg.y, bg.w, bg.h);
      ctx.restore();
    }
  }

  function isSelected(type, obj) {
    return SM.sel && SM.sel.type === type && SM.sel.id === obj.id;
  }

  function drawArea(area) {
    if (area.points.length < 2) { return; }
    var sel = isSelected('area', area);
    ctx.beginPath();
    ctx.moveTo(area.points[0][0], area.points[0][1]);
    for (var i = 1; i < area.points.length; i++) {
      ctx.lineTo(area.points[i][0], area.points[i][1]);
    }
    if (area.closed) { ctx.closePath(); }

    if (area.closed && area.points.length > 2) {
      ctx.globalAlpha = area.opacity;
      ctx.fillStyle = area.fill;
      ctx.fill();
      ctx.globalAlpha = 1;
    }
    ctx.lineWidth = (sel ? 2.5 : 1.5) / cam().zoom;
    ctx.strokeStyle = area.stroke;
    ctx.stroke();

    /* Centroid furniture — the link anchor and the name — is drawn unscaled so
       it stays legible and clickable at any zoom. */
    var centre = SM.areaCentre(area);
    var s = V.toScreen(centre.x, centre.y);
    var linking = SM.linking && SM.linking.from === area.id &&
                  SM.linking.from_type === 'area';
    var linked = SM.doc.links.some(function (l) {
      return (l.from === area.id && l.from_type === 'area') ||
             (l.to === area.id && l.to_type === 'area');
    });

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    if (linked || linking || sel) {
      var ar = V.ANCHOR_R;
      if (linking) {
        ctx.beginPath();
        ctx.arc(s.x, s.y, ar + 6, 0, Math.PI * 2);
        ctx.strokeStyle = '#e0a935';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
      ctx.beginPath();
      ctx.moveTo(s.x, s.y - ar);
      ctx.lineTo(s.x + ar, s.y);
      ctx.lineTo(s.x, s.y + ar);
      ctx.lineTo(s.x - ar, s.y);
      ctx.closePath();
      ctx.fillStyle = '#0d141c';
      ctx.fill();
      ctx.strokeStyle = area.stroke;
      ctx.lineWidth = sel ? 2.5 : 2;
      ctx.stroke();
    }

    if (area.name) {
      ctx.font = '600 11px "Segoe UI", system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = area.stroke;
      ctx.globalAlpha = 0.85;
      ctx.fillText(area.name.toUpperCase(), s.x,
        s.y + (linked || linking || sel ? V.ANCHOR_R + 13 : 0));
      ctx.textAlign = 'left';
    }
    ctx.restore();

    if (sel) {
      ctx.fillStyle = '#070b10';
      ctx.strokeStyle = area.stroke;
      ctx.lineWidth = 1.5 / cam().zoom;
      var r = 4 / cam().zoom;
      area.points.forEach(function (p) {
        ctx.beginPath();
        ctx.arc(p[0], p[1], r, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      });
    }
  }

  function drawPenPreview() {
    var pts = SM.pen.points;
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (var i = 1; i < pts.length; i++) { ctx.lineTo(pts[i][0], pts[i][1]); }
    if (SM.pen.cursor) { ctx.lineTo(SM.pen.cursor[0], SM.pen.cursor[1]); }
    ctx.lineWidth = 1.5 / cam().zoom;
    ctx.strokeStyle = '#35d0e0';
    ctx.setLineDash([6 / cam().zoom, 5 / cam().zoom]);
    ctx.stroke();
    ctx.setLineDash([]);

    var r = 3.5 / cam().zoom;
    ctx.fillStyle = '#35d0e0';
    pts.forEach(function (p) {
      ctx.beginPath();
      ctx.arc(p[0], p[1], r, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  function linkColor(link) {
    if (link.color) { return link.color; }
    if (link.kind === 'choice') { return '#e0a935'; }
    if (link.kind === 'reference') { return '#7b8fa3'; }
    return '#35d0e0';
  }

  function drawLink(link, index) {
    var g = linkGeometry(link, index);
    if (!g) { return; }
    var sel = isSelected('link', link);
    var z = cam().zoom;
    var col = linkColor(link);

    /* Trim the curve to the node edge so the arrow lands on the rim. An area
       anchor is a small marker rather than a full node, so it needs less. */
    var fromR = (link.from_type === 'area' ? V.ANCHOR_R : V.NODE_R) + 2;
    var toR = (link.to_type === 'area' ? V.ANCHOR_R : V.NODE_R) + 5;
    var startT = tAtRadius(g, 0, fromR / z);
    var endT = tAtRadius(g, 1, toR / z);

    ctx.beginPath();
    var first = quad(g.a, g.c, g.b, startT);
    ctx.moveTo(first.x, first.y);
    for (var t = startT; t <= endT; t += 0.02) {
      var p = quad(g.a, g.c, g.b, t);
      ctx.lineTo(p.x, p.y);
    }
    var tip = quad(g.a, g.c, g.b, endT);
    ctx.lineTo(tip.x, tip.y);

    ctx.lineWidth = (sel ? 2.6 : 1.6) / z;
    ctx.strokeStyle = col;
    ctx.globalAlpha = link.required ? 1 : 0.75;
    /* A required link is solid — it is a gate. Optional links are dashed. */
    ctx.setLineDash(link.required ? [] : [7 / z, 6 / z]);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.globalAlpha = 1;

    var prev = quad(g.a, g.c, g.b, Math.max(0, endT - 0.03));
    drawArrow(tip, Math.atan2(tip.y - prev.y, tip.x - prev.x), col, z);
  }

  function tAtRadius(g, from, radius) {
    var anchor = from === 0 ? g.a : g.b;
    var step = from === 0 ? 0.01 : -0.01;
    for (var t = from; t >= 0 && t <= 1; t += step) {
      var p = quad(g.a, g.c, g.b, t);
      if (Math.hypot(p.x - anchor.x, p.y - anchor.y) >= radius) { return t; }
    }
    return from === 0 ? 0.3 : 0.7;
  }

  function drawArrow(tip, angle, color, z) {
    var len = 9 / z, spread = 0.42;
    ctx.beginPath();
    ctx.moveTo(tip.x, tip.y);
    ctx.lineTo(tip.x - Math.cos(angle - spread) * len, tip.y - Math.sin(angle - spread) * len);
    ctx.lineTo(tip.x - Math.cos(angle + spread) * len, tip.y - Math.sin(angle + spread) * len);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  function drawLinkLabels() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.font = '10px "Segoe UI", system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    SM.doc.links.forEach(function (link, i) {
      if (!link.label) { return; }
      var g = linkGeometry(link, i);
      if (!g) { return; }
      var mid = quad(g.a, g.c, g.b, 0.5);
      var s = V.toScreen(mid.x, mid.y);
      var w = ctx.measureText(link.label).width + 10;
      ctx.fillStyle = 'rgba(7, 11, 16, 0.9)';
      ctx.fillRect(s.x - w / 2, s.y - 8, w, 16);
      ctx.fillStyle = linkColor(link);
      ctx.fillText(link.label, s.x, s.y);
    });
    ctx.textBaseline = 'alphabetic';
    ctx.textAlign = 'left';
  }

  function drawEventRadius(ev) {
    if (!ev.radius) { return; }
    var z = cam().zoom;
    ctx.beginPath();
    ctx.arc(ev.x, ev.y, ev.radius, 0, Math.PI * 2);
    ctx.strokeStyle = SM.eventColor(ev);
    ctx.globalAlpha = isSelected('event', ev) ? 0.55 : 0.22;
    ctx.lineWidth = 1 / z;
    ctx.setLineDash([5 / z, 6 / z]);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.globalAlpha = 1;
  }

  function drawEventNode(ev) {
    var s = V.toScreen(ev.x, ev.y);
    if (s.x < -160 || s.y < -160 || s.x > V.width + 160 || s.y > V.height + 160) {
      return;
    }
    var sel = isSelected('event', ev);
    var col = SM.eventColor(ev);
    var r = V.NODE_R;

    if (SM.linking && SM.linking.from === ev.id &&
        SM.linking.from_type !== 'area') {
      ctx.beginPath();
      ctx.arc(s.x, s.y, r + 7, 0, Math.PI * 2);
      ctx.strokeStyle = '#e0a935';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    ctx.beginPath();
    ctx.arc(s.x, s.y, r, 0, Math.PI * 2);
    ctx.fillStyle = '#0d141c';
    ctx.fill();
    ctx.lineWidth = sel ? 3 : 2;
    ctx.strokeStyle = col;
    ctx.stroke();

    /* Inner dot marks an event that gates something else. */
    if (SM.doc.links.some(function (l) { return l.from === ev.id && l.required; })) {
      ctx.beginPath();
      ctx.arc(s.x, s.y, 4, 0, Math.PI * 2);
      ctx.fillStyle = col;
      ctx.fill();
    }

    /* Count of choices, so branchy events read at a glance. */
    if (ev.options.length) {
      ctx.font = '600 9px "Segoe UI", system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = '#070b10';
      var bx = s.x + r - 2, by = s.y - r + 2;
      ctx.beginPath();
      ctx.arc(bx, by, 7, 0, Math.PI * 2);
      ctx.fillStyle = col;
      ctx.fill();
      ctx.fillStyle = '#070b10';
      ctx.fillText(String(ev.options.length), bx, by + 3);
      ctx.textAlign = 'left';
    }

    var label = ev.title || '(untitled)';
    ctx.font = (sel ? '600 ' : '') + '12px "Segoe UI", system-ui, sans-serif';
    ctx.textAlign = 'center';
    var w = ctx.measureText(label).width;
    ctx.fillStyle = 'rgba(7, 11, 16, 0.86)';
    ctx.fillRect(s.x - w / 2 - 5, s.y + r + 4, w + 10, 16);
    ctx.fillStyle = sel ? '#fff' : '#c8d6e2';
    ctx.fillText(label, s.x, s.y + r + 16);
    ctx.textAlign = 'left';
  }

  function drawNote(note) {
    var s = V.toScreen(note.x, note.y);
    var px = Math.max(9, note.size * cam().zoom);
    var sel = isSelected('note', note);
    ctx.font = (sel ? '600 ' : '') + px + 'px "Segoe UI", system-ui, sans-serif';
    var lines = String(note.text || '').split('\n');
    var w = 0;
    lines.forEach(function (l) { w = Math.max(w, ctx.measureText(l).width); });

    ctx.fillStyle = 'rgba(7, 11, 16, 0.7)';
    ctx.fillRect(s.x - 5, s.y - px, w + 10, px * lines.length + 8);
    if (sel) {
      ctx.strokeStyle = '#35d0e0';
      ctx.lineWidth = 1;
      ctx.strokeRect(s.x - 5, s.y - px, w + 10, px * lines.length + 8);
    }
    ctx.fillStyle = note.color;
    lines.forEach(function (line, i) {
      ctx.fillText(line, s.x, s.y + i * px);
    });
  }

})(window.SM);
