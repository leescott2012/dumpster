const CACHE_NAME = 'dumpster-v2';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.svg',
  '/apple-touch-icon.png',
  '/icon-192.png',
  '/icon-512.png',
];

// Install — precache static assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch(() => {
        // Some assets may not exist yet in dev, continue
      });
    })
  );
  self.skipWaiting();
});

// Activate — clean old caches + enable navigation preload
self.addEventListener('activate', (event) => {
  event.waitUntil(
    Promise.all([
      // Clear old caches
      caches.keys().then((names) =>
        Promise.all(
          names
            .filter((name) => name !== CACHE_NAME)
            .map((name) => caches.delete(name))
        )
      ),
      // Enable navigation preload if supported (faster page loads on iOS 17+)
      self.registration.navigationPreload?.enable().catch(() => {}),
    ])
  );
  self.clients.claim();
});

// Fetch — network-first for navigations, stale-while-revalidate for assets
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Navigation requests — network first with preload
  if (event.request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          // Use navigation preload response if available
          const preloadResp = await event.preloadResponse;
          if (preloadResp) return preloadResp;

          return await fetch(event.request);
        } catch {
          const cached = await caches.match('/index.html');
          return cached || new Response('Offline', { status: 503 });
        }
      })()
    );
    return;
  }

  // Sample photos — cache first (they don't change)
  if (url.pathname.startsWith('/sample-photos/')) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((resp) => {
          if (resp.ok) {
            const clone = resp.clone();
            caches.open(CACHE_NAME).then((c) => c.put(event.request, clone));
          }
          return resp;
        });
      })
    );
    return;
  }

  // Other assets — stale-while-revalidate
  event.respondWith(
    caches.match(event.request).then((cached) => {
      const fetchPromise = fetch(event.request)
        .then((resp) => {
          if (resp.ok && resp.type !== 'opaque') {
            const clone = resp.clone();
            caches.open(CACHE_NAME).then((c) => c.put(event.request, clone));
          }
          return resp;
        })
        .catch(() => cached);

      return cached || fetchPromise;
    })
  );
});
