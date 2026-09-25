// Matric — service worker.
// HTML is always fetched from network (no caching) so we never serve
// stale redirect pages. Only static assets are cached, for speed.

const CACHE = 'matric-v3';

const ASSETS = [
  './manifest.json',
  './v2/css/tokens.css',
  './v2/css/nav.css',
  './v2/css/notifications.css',
  './v2/css/topbar.css',
  './v2/js/supabase.js',
  './v2/js/bottom-nav.js',
  './v2/js/notifications.js',
  './v2/js/pwa.js',
  './v2/js/push.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/maskable-192.png',
  './icons/maskable-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((c) => c.addAll(ASSETS))
      .catch(() => {})
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
  if (url.origin !== self.location.origin) return;

  // HTML — always network. No caching. Prevents stale redirect pages.
  const accept = req.headers.get('accept') || '';
  if (accept.includes('text/html') || url.pathname.endsWith('.html') || url.pathname.endsWith('/')) {
    return; // let the browser handle it directly
  }

  // Static assets — cache-first, network in the background.
  event.respondWith(
    caches.match(req).then((cached) => {
      const fetched = fetch(req).then((res) => {
        if (res && res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || fetched;
    })
  );
});

// Push + notification handlers unchanged
self.addEventListener('push', (event) => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch (_) { payload = { title: 'Matric', body: event.data ? event.data.text() : '' }; }

  const title = payload.title || 'Matric';
  const options = {
    body: payload.body || '',
    icon: payload.icon || './icons/icon-192.png',
    badge: payload.badge || './icons/icon-192.png',
    tag: payload.tag || undefined,
    renotify: !!payload.tag,
    vibrate: [80, 40, 80],
    data: { url: payload.url || './v2/pages/dashboard.html', id: payload.id || null },
    timestamp: Date.now(),
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './v2/pages/dashboard.html';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.includes('github.io/uniconnect') && 'focus' in c) {
          return c.focus().then(() => { if (c.navigate) return c.navigate(target); });
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
