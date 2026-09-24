// v2/js/back-button.js
// Wires any element with [data-back-to] to navigate back intelligently:
//   - If we came from another page in this app, use history.back()
//   - Otherwise navigate to the data-back-to fallback
// The <a href> stays as-is so right-click / middle-click still work.

(function () {
  function sameOrigin(ref) {
    if (!ref) return false;
    try { return new URL(ref).origin === location.origin; }
    catch { return false; }
  }

  function goBack(el) {
    const fallback = el.dataset.backTo || 'dashboard.html';
    if (window.history.length > 1 && sameOrigin(document.referrer)) {
      history.back();
    } else {
      location.href = fallback;
    }
  }

  function init() {
    document.querySelectorAll('[data-back-to]').forEach(function (el) {
      el.addEventListener('click', function (e) {
        // Respect modifier clicks — let the browser handle them natively.
        if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        e.preventDefault();
        goBack(el);
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
