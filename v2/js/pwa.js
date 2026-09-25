// v2/js/pwa.js — PWA plumbing.
// Registers the service worker and exposes install helpers to other pages.

(function () {
  'use strict';

  // ---- Service worker registration ----
  // All app pages live at /v2/pages/*.html; sw.js lives at the repo root.
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker
        .register('../../sw.js')
        .catch((err) => console.warn('[pwa] service worker registration failed:', err));
    });
  }

  // ---- Install prompt capture ----
  let deferredPrompt = null;

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    window.__matric_install_available = true;
    window.dispatchEvent(new CustomEvent('matric:install-ready'));
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    window.__matric_install_available = false;
    window.dispatchEvent(new CustomEvent('matric:installed'));
  });

  // ---- Public API ----
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

  window.matric.isIOS = function () {
    return /iphone|ipad|ipod/i.test(navigator.userAgent)
        || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  };
})();
