/* MonWe Trading — Service Worker
   Stratégie:
   - API (/api/*) : toujours réseau (jamais de cache, données temps réel)
   - Pages/assets : network-first avec repli sur cache (offline léger)
*/
const CACHE = 'monwe-trading-v1';
const ASSETS = [
  '/dashboard.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
  '/apple-touch-icon.png',
  '/favicon.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);

  // Ne jamais mettre l'API en cache (signaux temps réel)
  if (url.pathname.startsWith('/api/')) {
    return; // laisse passer au réseau normalement
  }

  // Network-first pour le reste, repli cache si hors-ligne
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res && res.status === 200 && e.request.method === 'GET') {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('/dashboard.html')))
  );
});
