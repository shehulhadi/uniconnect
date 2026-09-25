// UniConnect — minimal service worker.
// Its job is to make the app installable and to keep the shell usable
// offline. It never caches Supabase API traffic.

const CACHE = 'uniconnect-v1';

const CORE = [
  './manifest.json',
  './v2/pages/landing.html',
  './v2/pages/login.html',
  './v2/pages/dashboard.html',
  './v2/css/tokens.css',
  './v2/css/nav.css',
  './v2/css/notifications.css',
  './v2/css/topbar.css',
  './v2/js/supabase.js',
  './v2/js/bottom-nav.js',
  './v2/js/notifications.js',
  './v2/js/pwa.js',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((c) => c.addAll(CORE))
      .catch(() => {})   // best-effort; missing a file must not block install
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Never intercept Supabase or other cross-origin API calls.
  if (url.origin !== self.location.origin) return;

  // Network-first, cache fallback for offline.
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(req))
  );
});
