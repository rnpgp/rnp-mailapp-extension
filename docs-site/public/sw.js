/* RNP docs site — offline support.
   Stale-while-revalidate for same-origin GET requests: serve from cache
   immediately, refresh the cache in the background. Pages visited once stay
   readable offline. Bump CACHE_VERSION to invalidate after a deploy. */
const CACHE_VERSION = 'rnp-docs-v1';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) =>
      cache.addAll([
        '/',
        '/favicon.svg',
        '/rnp-symbol.svg',
        '/getting-started/installation/',
        '/getting-started/first-launch/',
        '/key-management/',
        '/trust-verification/',
        '/keyserver/',
        '/using-with-mail/',
        '/security/',
        '/troubleshooting/',
        '/faq/',
      ]),
    ),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE_VERSION).map((key) => caches.delete(key))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;

  event.respondWith(
    caches.open(CACHE_VERSION).then(async (cache) => {
      const cached = await cache.match(request);
      const fetched = fetch(request)
        .then((response) => {
          if (response.ok) cache.put(request, response.clone());
          return response;
        })
        .catch(() => cached);
      return cached || fetched;
    }),
  );
});
