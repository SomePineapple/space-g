/* app.js — wiring. Owns the sidebar list, the checks panel, the status line,
 * toasts and boot order. Nothing here knows how anything is drawn or stored. */

(function (SM) {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var canvas, docName, eventList, eventSearch, eventCount,
      issueList, issueCount, statusEl, dirtyDot, toastEl, hintEl;

  var toastTimer = null;

  SM.toast = function (message, isError) {
    if (!toastEl) { return; }
    toastEl.textContent = message;
    toastEl.className = 'on' + (isError ? ' err' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.className = ''; }, 2600);
  };

  function boot() {
    canvas = $('canvas');
    docName = $('doc-name');
    eventList = $('event-list');
    eventSearch = $('event-search');
    eventCount = $('event-count');
    issueList = $('issue-list');
    issueCount = $('issue-count');
    statusEl = $('storage-status');
    dirtyDot = $('dirty-dot');
    toastEl = $('toast');
    hintEl = $('tool-hint');

    SM.view.attach(canvas);
    SM.attachTools(canvas);
    SM.inspector.attach($('inspector'));

    wireButtons();
    wireBus();

    window.addEventListener('resize', SM.view.resize);
    window.addEventListener('beforeunload', function (e) {
      if (!SM.storage.dirty) { return undefined; }
      e.preventDefault();
      e.returnValue = '';
      return '';
    });

    restore();
  }

  /* Autosave is the last known state of the session, so it is adopted without
     asking — the file on disk is only ever ahead of it if another tool wrote
     it, which the status line makes visible. */
  function restore() {
    var saved = SM.storage.readAutosave();
    if (saved && saved.doc) {
      SM.doc = SM.normalize(saved.doc);
      SM.storage.fileName = saved.fileName || '';
      SM.afterDocSwap();
      SM.storage.dirty = false;
      SM.view.fit();
      SM.toast('Restored your last session');
    } else {
      SM.doc = SM.newDoc();
      SM.afterDocSwap();
      SM.storage.dirty = false;
      SM.view.resetZoom();
    }
    SM.storage.restoreHandle().then(refreshStatus);
    SM.setTool('select');
    refreshAll();
  }

  function wireButtons() {
    $('btn-new').onclick = function () { SM.storage.newDocument(); };
    $('btn-open').onclick = function () { SM.storage.open(); };
    $('btn-save').onclick = function () { SM.storage.save(); };
    $('btn-saveas').onclick = function () { SM.storage.saveAs(); };
    $('btn-fit').onclick = function () { SM.view.fit(); refreshZoom(); };
    $('btn-reset-zoom').onclick = function () { SM.view.resetZoom(); refreshZoom(); };

    docName.addEventListener('input', function () {
      SM.push('docname');
      SM.doc.name = docName.value;
      SM.changed();
    });

    eventSearch.addEventListener('input', renderEventList);

    Array.prototype.forEach.call(document.querySelectorAll('.tool'), function (b) {
      b.onclick = function () { SM.setTool(b.getAttribute('data-tool')); };
    });

    $('file-input').addEventListener('change', function (e) {
      var file = e.target.files && e.target.files[0];
      if (!file) { return; }
      file.text().then(function (text) {
        if (SM.storage.loadText(text)) {
          SM.storage.fileName = file.name;
          SM.toast('Opened ' + file.name);
          refreshAll();
        }
      });
      e.target.value = '';
    });

    $('image-input').addEventListener('change', function (e) {
      SM.storage.loadBackgroundImage(e.target.files && e.target.files[0]);
      e.target.value = '';
    });
  }

  function wireBus() {
    SM.bus.on('doc', refreshAll);
    SM.bus.on('list', function () { renderEventList(); renderIssues(); });
    SM.bus.on('selection', function () { renderEventList(); });
    SM.bus.on('tool', refreshTool);
    SM.bus.on('storage', refreshStatus);
    SM.bus.on('zoom', refreshZoom);
    SM.bus.on('cursor', function (w) {
      $('hud-coords').textContent = Math.round(w.x) + ', ' + Math.round(w.y);
    });
  }

  function refreshAll() {
    docName.value = SM.doc.name;
    renderEventList();
    renderIssues();
    refreshStatus();
    refreshZoom();
  }

  function refreshTool() {
    Array.prototype.forEach.call(document.querySelectorAll('.tool'), function (b) {
      b.classList.toggle('on', b.getAttribute('data-tool') === SM.tool);
    });
    hintEl.textContent = SM.toolHint();
  }

  function refreshZoom() {
    $('hud-zoom').textContent = Math.round(SM.doc.map.view.zoom * 100) + '%';
  }

  function refreshStatus() {
    var S = SM.storage;
    dirtyDot.classList.toggle('on', S.dirty);

    var parts = [];
    if (S.handle) {
      parts.push(S.fileName + (S.handleGranted ? '' : ' — click Save to reconnect'));
    } else if (S.supportsFs) {
      parts.push('No file yet — use Save as');
    } else {
      parts.push('Download mode — Save writes a file to your downloads');
    }
    parts.push(S.dirty ? 'unsaved changes (autosaved)' : 'up to date');
    statusEl.textContent = parts.join(' · ');
  }

  function renderEventList() {
    var filter = (eventSearch.value || '').toLowerCase().trim();
    /* The list is rebuilt on every selection, so keep the scroll position —
       otherwise clicking an item far down snaps the list back to the top. */
    var scroll = eventList.scrollTop;
    eventList.innerHTML = '';
    eventCount.textContent = SM.doc.events.length;

    SM.doc.events
      .filter(function (ev) {
        if (!filter) { return true; }
        return (ev.title + ' ' + ev.type + ' ' + ev.tags.join(' '))
          .toLowerCase().indexOf(filter) >= 0;
      })
      .forEach(function (ev) {
        var li = document.createElement('li');
        if (SM.sel && SM.sel.type === 'event' && SM.sel.id === ev.id) {
          li.className = 'on';
        }
        var dot = document.createElement('span');
        dot.className = 'swatch';
        dot.style.background = SM.eventColor(ev);
        var title = document.createElement('span');
        title.className = 'row-title';
        title.textContent = ev.title || '(untitled)';
        var type = document.createElement('span');
        type.className = 'row-type';
        type.textContent = ev.type;
        li.appendChild(dot);
        li.appendChild(title);
        li.appendChild(type);
        li.onclick = function () { SM.inspector.focusEvent(ev.id); };
        eventList.appendChild(li);
      });

    if (!eventList.children.length) {
      var empty = document.createElement('li');
      empty.style.color = 'var(--text-dim)';
      empty.style.cursor = 'default';
      empty.textContent = SM.doc.events.length
        ? 'Nothing matches that filter.'
        : 'No events yet — press E and click the map.';
      eventList.appendChild(empty);
    }

    eventList.scrollTop = scroll;
  }

  function renderIssues() {
    var issues = SM.issues();
    issueList.innerHTML = '';
    issueCount.textContent = issues.length ? issues.length : '';

    if (!issues.length) {
      var ok = document.createElement('li');
      ok.style.color = 'var(--good)';
      ok.style.cursor = 'default';
      ok.textContent = 'Nothing to flag.';
      issueList.appendChild(ok);
      return;
    }

    issues.slice(0, 40).forEach(function (issue) {
      var li = document.createElement('li');
      li.textContent = issue.text;
      if (issue.bad) { li.className = 'bad'; }
      li.onclick = function () { SM.inspector.focusNode(issue.type, issue.id); };
      issueList.appendChild(li);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

})(window.SM);
