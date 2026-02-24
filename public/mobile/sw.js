// Service Worker for PWA
const CACHE_NAME = 'openclaw-chat-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/login.html'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => response || fetch(event.request))
  );
});
