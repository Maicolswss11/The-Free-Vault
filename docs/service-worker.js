const CACHE_NAME = "the-free-vault-v3-2-account-complete";
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./cloud-sync.js",
  "./auth.js",
  "./config.js",
  "./manifest.webmanifest",
  "./placeholders/game-placeholder.svg",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
    ))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  const isData = ["/games.json", "/history.json", "/catalog.json"]
    .some((ending) => url.pathname.endsWith(ending));
  const isCover = url.pathname.includes("/assets/covers/");

  if (isData) {
    const canonicalUrl = new URL(event.request.url);
    canonicalUrl.search = "";
    const cacheKey = new Request(canonicalUrl.toString());
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {
            caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, response.clone()));
          }
          return response;
        })
        .catch(() => caches.match(cacheKey))
    );
    return;
  }

  if (isCover) {
    event.respondWith(
      caches.match(event.request).then((cached) => cached || fetch(event.request).then((response) => {
        if (response.ok) caches.open(CACHE_NAME).then((cache) => cache.put(event.request, response.clone()));
        return response;
      }))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
