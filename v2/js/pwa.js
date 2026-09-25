// v2/js/pwa.js — PWA registration + install helpers.

(function () {
  'use strict';

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      // Determine the app root by walking up from the current page.
      // Pages live at /<repo>/v2/pages/*.html → SW is at /<repo>/sw.js
      const path = location.pathname;
      const m = path.match(/^(.*\/)v2\/pages\//);
      const swUrl = m ? m[1] + 'sw.js' : '../../sw.js';

      navigator.serviceWorker.register(swUrl, { scope: m ? m[1] : '../../' })
        .catch((err) => console.warn('[pwa] sw registration failed', err));
    });
  }

  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    window.dispatchEvent(new CustomEvent('matric:install-ready'));
  });
  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    window.dispatchEvent(new CustomEvent('matric:installed'));
  });

  window.matric = window.matric || {};
  window.matric.install = async function () {
    if (!deferredPrompt) return { ok: false, reason: 'unavailable' };
    deferredPrompt.prompt();
    const choice = await deferredPrompt.userChoice;
    deferredPrompt = null;
    return { ok: choice.outcome === 'accepted', outcome: choice.outcome };
  };
  window.matric.isInstalled = function () {
    return window.matchMedia('(display-mode: standalone)').matches
        || window.navigator.standalone === true;
  };
})();
