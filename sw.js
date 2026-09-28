/* Quiet Trace service worker: keeps a copy of the app so it plays with no connection.
 * Network first (so updates arrive as soon as they're published), falling back to
 * the saved copy when offline or when the network is too slow. */
const CACHE = 'quiet-trace-v1';
const FILES = [
  './',
  './index.html',
  './styles.css',
  './shapes.js',
  './app.js',
  './manifest.webmanifest',
  './icons/icon.svg',
  './icons/icon-180.png',
  './icons/icon-512.png',
];
const NETWORK_WAIT_MS = 2500;

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(fromNetworkOrCache(req));
});

async function fromNetworkOrCache(req) {
  const cache = await caches.open(CACHE);
  const network = fetch(req).then((res) => {
    if (res.ok) cache.put(req, res.clone());
    return res;
  });
  const timeout = new Promise((resolve) => setTimeout(resolve, NETWORK_WAIT_MS));
  try {
    const res = await Promise.race([network, timeout]);
    if (res) return res;
  } catch (_) { /* offline */ }
  const saved = await cache.match(req, { ignoreSearch: true })
    || (req.mode === 'navigate' && await cache.match('./index.html'));
  return saved || network;
}
