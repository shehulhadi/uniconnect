// Matric — service worker, minimal.
// No caching. No fetch interception. Only push handling.
// The app should never fail to open because of this file.

self.addEventListener('install', (e) => self.skipWaiting());

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.map(k => caches.delete(k))))
  );
  self.clients.claim();
});

// No fetch handler — browser default behaviour, always network.

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
    vibrate: [80, 40, 80],
    data: { url: payload.url || './v2/pages/dashboard.html' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './v2/pages/dashboard.html';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus().then(() => { if (c.navigate) return c.navigate(target); });
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
