var CACHE_NAME = 'comisigner-driver-v2';
var SHELL_FILES = [
  './manifest.json',
  './vendor/signature_pad.umd.min.js',
  './vendor/supabase.js',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(SHELL_FILES);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(
        names.filter(function (name) { return name !== CACHE_NAME; })
             .map(function (name) { return caches.delete(name); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);

  // only handle same-origin GET requests; let everything else
  // (Supabase API calls, storage uploads/downloads) go straight to the network
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) {
    return;
  }

  // HTML navigations: always try the network first so a redeploy is picked up
  // immediately; fall back to a cached copy only when offline.
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).then(function (response) {
        var clone = response.clone();
        caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
        return response;
      }).catch(function () {
        return caches.match(event.request);
      })
    );
    return;
  }

  // static assets (libraries, icons, manifest): cache-first is fine, filenames don't change
  event.respondWith(
    caches.match(event.request).then(function (cached) {
      if (cached) return cached;
      return fetch(event.request).then(function (response) {
        if (response.ok) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function (cache) {
            cache.put(event.request, clone);
          });
        }
        return response;
      });
    })
  );
});
