// Stands in for what the webOS app provides, so the script runs on a Mac.
(function () {
  window.launchParams = {};

  window.__errors = [];
  window.addEventListener('error', function (e) { window.__errors.push(String(e.message) + ' @' + String(e.filename).split('/').pop() + ':' + e.lineno); });
  window.addEventListener('unhandledrejection', function (e) { window.__errors.push('rejection ' + String(e.reason)); });

  // Best quality on by default; a choice made in the settings is kept.
  try {
    var KEY = 'ytaf-configuration';
    var stored = JSON.parse(window.localStorage.getItem(KEY) || 'null') || {};
    if (!('forceHighResVideo' in stored)) {
      stored.forceHighResVideo = true;
      window.localStorage.setItem(KEY, JSON.stringify(stored));
    }
  } catch (e) {}

  // The TV page lays out in a 16:9 area and leaves bars on a 16:10 screen. The interface is stretched taller to fill the screen, with nothing cut off, and the video is squeezed back to its own shape. It is off by default, as the stretch distorts the menu icons; F5 switches it on.
  function fit() {
    var stretch = (16 * window.innerHeight) / (9 * window.innerWidth);
    var on = window.localStorage.getItem('yt-fill') === '1';
    var style = document.getElementById('yt-fill');
    if (!style) {
      style = document.createElement('style');
      style.id = 'yt-fill';
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = on && stretch > 1.005
      ? 'html{overflow:hidden!important;background:#000}body{transform:scaleY(' + stretch + ');transform-origin:50% 50%}video{transform:scaleY(' + (1 / stretch) + ')!important}'
      : '';
  }
  fit();
  window.addEventListener('resize', fit);
  document.addEventListener('DOMContentLoaded', fit);
  // For the host app's menu: switches the fill on or off.
  window.__ytToggleFill = function () {
    window.localStorage.setItem('yt-fill', window.localStorage.getItem('yt-fill') === '1' ? '0' : '1');
    fit();
  };
  window.addEventListener('keydown', function (e) {
    if (e.key !== 'F5') return;
    e.preventDefault();
    window.localStorage.setItem('yt-fill', window.localStorage.getItem('yt-fill') === '1' ? '0' : '1');
    fit();
  }, true);

  // F1-F4 stand in for the remote's red, green, yellow and blue buttons; green opens the settings.
  var keys = { F1: 403, F2: 404, F3: 405, F4: 406 };
  function remote(type) {
    return function (e) {
      var code = keys[e.key];
      if (!code || e.__fromShim) return;
      e.stopImmediatePropagation();
      e.preventDefault();
      var copy = new KeyboardEvent(type, { key: e.key, bubbles: true, cancelable: true });
      // keyCode is read-only, so it is set on the instance.
      Object.defineProperty(copy, 'keyCode', { get: function () { return code; } });
      Object.defineProperty(copy, 'which', { get: function () { return code; } });
      // The script reads the colour buttons from charCode.
      Object.defineProperty(copy, 'charCode', { get: function () { return code; } });
      copy.__fromShim = true;
      (document.activeElement || document.body).dispatchEvent(copy);
    };
  }
  // For the host app: a coloured button pressed on the Magic Remote, as the page's own script expects it (red 403, green 404, yellow 405, blue 406).
  window.__ytKey = function (code) {
    ['keydown', 'keyup'].forEach(function (type) {
      var event = new KeyboardEvent(type, { bubbles: true, cancelable: true });
      Object.defineProperty(event, 'keyCode', { get: function () { return code; } });
      Object.defineProperty(event, 'which', { get: function () { return code; } });
      Object.defineProperty(event, 'charCode', { get: function () { return code; } });
      event.__fromShim = true;
      (document.activeElement || document.body).dispatchEvent(event);
    });
  };
  window.addEventListener('keydown', remote('keydown'), true);
  window.addEventListener('keyup', remote('keyup'), true);
})();
