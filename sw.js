const CACHE_NAME = 'telesales-pwa-v1';
const ASSETS = [
  './',
  './Telesales%20Monitor%20App.dc.html',
  './support.js',
  './ios-frame.jsx',
  './manifest.json',
  './icon.svg',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/tokens/fonts.css',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/tokens/colors.css',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/tokens/typography.css',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/tokens/spacing.css',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/styles.css',
  './_ds/askeva-design-system-f369da11-358d-4fcb-8a05-42d32204ae78/_ds_bundle.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS).catch(() => {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }
      return fetch(event.request).then((networkResponse) => {
        if (
          networkResponse &&
          networkResponse.status === 200 &&
          event.request.method === 'GET'
        ) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return networkResponse;
      }).catch(() => {});
    })
  );
});
