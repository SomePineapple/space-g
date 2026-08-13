/* storage.js — three layers of safety against losing work:
 *
 *  1. Autosave to localStorage on every edit (debounced). Survives a crash,
 *     a reload or a closed tab, and is restored on the next visit.
 *  2. A real file on disk. In Chrome/Edge the page keeps a file handle and
 *     writes straight into it on Save; the handle is remembered in IndexedDB
 *     so reopening the page reconnects to the same file after one click.
 *  3. Download / file-picker fallback everywhere else (Firefox, Safari).
 *
 * The file is the source of truth for the project; localStorage is only a
 * crash net, and the UI says so when the two disagree. */

(function (SM) {
  'use strict';

  var AUTOSAVE_KEY = 'space-g.story-maker.autosave';
  var S = {};
  SM.storage = S;

  S.dirty = false;
  S.handle = null;
  S.fileName = '';
  S.supportsFs = typeof window.showSaveFilePicker === 'function';

  var autosaveTimer = null;

  /* ------------------------------------------------------------ autosave */

  SM.bus.on('dirty', function () {
    S.dirty = true;
    SM.bus.emit('storage');
    clearTimeout(autosaveTimer);
    autosaveTimer = setTimeout(autosave, 500);
  });

  function autosave() {
    try {
      localStorage.setItem(AUTOSAVE_KEY, JSON.stringify({
        savedAt: new Date().toISOString(),
        fileName: S.fileName,
        doc: SM.doc
      }));
    } catch (err) {
      /* Quota is the realistic failure, usually a large background image. */
      SM.toast('Autosave failed: ' + err.message, true);
    }
  }
  S.autosave = autosave;

  S.readAutosave = function () {
    try {
      var raw = localStorage.getItem(AUTOSAVE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (err) {
      return null;
    }
  };

  S.clearAutosave = function () {
    try { localStorage.removeItem(AUTOSAVE_KEY); } catch (err) { /* ignore */ }
  };

  /* --------------------------------------------------- indexeddb handles */

  function idb() {
    return new Promise(function (resolve, reject) {
      var req = indexedDB.open('space-g-story-maker', 1);
      req.onupgradeneeded = function () {
        req.result.createObjectStore('handles');
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }

  function idbPut(key, value) {
    return idb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction('handles', 'readwrite');
        tx.objectStore('handles').put(value, key);
        tx.oncomplete = resolve;
        tx.onerror = function () { reject(tx.error); };
      });
    }).catch(function () { /* handle persistence is a convenience, not a need */ });
  }

  function idbGet(key) {
    return idb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction('handles', 'readonly');
        var req = tx.objectStore('handles').get(key);
        req.onsuccess = function () { resolve(req.result || null); };
        req.onerror = function () { reject(req.error); };
      });
    }).catch(function () { return null; });
  }

  /* Restore the previous file handle without prompting — permission can only
     be requested from a user gesture, so a still-granted handle reconnects
     silently and anything else waits for the next Save. */
  S.restoreHandle = function () {
    if (!S.supportsFs) { return Promise.resolve(false); }
    return idbGet('file').then(function (handle) {
      if (!handle) { return false; }
      return handle.queryPermission({ mode: 'readwrite' }).then(function (state) {
        S.handle = handle;
        S.fileName = handle.name;
        S.handleGranted = state === 'granted';
        SM.bus.emit('storage');
        return true;
      });
    }).catch(function () { return false; });
  };

  /* ---------------------------------------------------------------- save */

  function serialize() {
    SM.doc.updated = new Date().toISOString();
    return JSON.stringify(SM.doc, null, 2);
  }
  S.serialize = serialize;

  S.save = function () {
    if (!S.handle) { return S.saveAs(); }
    return ensurePermission().then(function (ok) {
      if (!ok) {
        SM.toast('Permission denied for that file — use Save as', true);
        return false;
      }
      return writeHandle();
    });
  };

  function ensurePermission() {
    if (!S.handle.requestPermission) { return Promise.resolve(true); }
    return S.handle.queryPermission({ mode: 'readwrite' }).then(function (state) {
      if (state === 'granted') { return true; }
      return S.handle.requestPermission({ mode: 'readwrite' })
        .then(function (s) { return s === 'granted'; });
    });
  }

  function writeHandle() {
    return S.handle.createWritable().then(function (stream) {
      return stream.write(serialize()).then(function () {
        return stream.close();
      });
    }).then(function () {
      S.dirty = false;
      S.handleGranted = true;
      autosave();
      SM.bus.emit('storage');
      SM.toast('Saved to ' + S.fileName);
      return true;
    }).catch(function (err) {
      SM.toast('Save failed: ' + err.message, true);
      return false;
    });
  }

  S.saveAs = function () {
    var suggested = fileNameFor(SM.doc.name);
    if (!S.supportsFs) {
      download(suggested, serialize());
      S.dirty = false;
      SM.bus.emit('storage');
      SM.toast('Downloaded ' + suggested);
      return Promise.resolve(true);
    }
    return window.showSaveFilePicker({
      suggestedName: suggested,
      types: [{ description: 'Story map', accept: { 'application/json': ['.json'] } }]
    }).then(function (handle) {
      S.handle = handle;
      S.fileName = handle.name;
      return idbPut('file', handle).then(writeHandle);
    }).catch(function (err) {
      if (err && err.name === 'AbortError') { return false; }
      SM.toast('Save failed: ' + err.message, true);
      return false;
    });
  };

  function fileNameFor(name) {
    var base = String(name || 'story-map')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
    return (base || 'story-map') + '.json';
  }

  function download(name, text) {
    var blob = new Blob([text], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  /* ---------------------------------------------------------------- open */

  S.open = function () {
    if (!confirmDiscard()) { return Promise.resolve(false); }
    if (!S.supportsFs) {
      document.getElementById('file-input').click();
      return Promise.resolve(true);
    }
    return window.showOpenFilePicker({
      types: [{ description: 'Story map', accept: { 'application/json': ['.json'] } }],
      multiple: false
    }).then(function (handles) {
      var handle = handles[0];
      return handle.getFile().then(function (file) {
        return file.text().then(function (text) {
          if (!S.loadText(text)) { return false; }
          S.handle = handle;
          S.fileName = handle.name;
          S.handleGranted = true;
          return idbPut('file', handle).then(function () {
            SM.bus.emit('storage');
            return true;
          });
        });
      });
    }).catch(function (err) {
      if (err && err.name === 'AbortError') { return false; }
      SM.toast('Open failed: ' + err.message, true);
      return false;
    });
  };

  S.loadText = function (text) {
    var raw;
    try {
      raw = JSON.parse(text);
    } catch (err) {
      SM.toast('That file is not valid JSON', true);
      return false;
    }
    if (raw && raw.schema && raw.schema !== SM.SCHEMA) {
      SM.toast('Not a story map file (' + raw.schema + ')', true);
      return false;
    }
    S.adopt(SM.normalize(raw));
    return true;
  };

  S.adopt = function (doc) {
    SM.doc = doc;
    SM.sel = null;
    SM.history.past.length = 0;
    SM.history.future.length = 0;
    SM.afterDocSwap();
    S.dirty = false;
    SM.view.fit();
    SM.bus.emit('storage');
  };

  S.newDocument = function () {
    if (!confirmDiscard()) { return; }
    S.handle = null;
    S.fileName = '';
    S.adopt(SM.newDoc());
    S.dirty = false;
    SM.bus.emit('storage');
  };

  function confirmDiscard() {
    if (!S.dirty) { return true; }
    return window.confirm('This map has unsaved changes. Discard them?');
  }

  /* --------------------------------------------------------- background */

  S.loadBackgroundImage = function (file) {
    if (!file) { return; }
    if (file.size > 6 * 1024 * 1024) {
      SM.toast('Image is over 6 MB — it is stored inside the map file', true);
    }
    var reader = new FileReader();
    reader.onload = function () {
      var img = new Image();
      img.onload = function () {
        SM.push();
        var w = img.naturalWidth * 4;      /* 1 px of art = 4 world units  */
        var h = img.naturalHeight * 4;
        SM.doc.map.background = {
          name: file.name,
          src: reader.result,
          x: Math.round(-w / 2),
          y: Math.round(-h / 2),
          w: Math.round(w),
          h: Math.round(h),
          opacity: 0.7
        };
        SM.changed();
        SM.inspector.render();
        SM.view.fit();
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  };

})(window.SM);
