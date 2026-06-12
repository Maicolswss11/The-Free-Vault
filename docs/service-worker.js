
// Previous stable cache: the-free-vault-v4-7-1-franchise-bulk-selection
// Earlier stable cache: the-free-vault-v4-7-personal-recommendations
// Earlier stable cache: the-free-vault-v4-6-franchises-editorial
// Earlier stable cache: the-free-vault-v4-5-1-progress-rating-hotfix
const CACHE_NAME = "the-free-vault-v4-7-2-editorial-steam-metadata";
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./cloud-sync.js",
  "./social.js",
  "./steam.js",
  "./catalog-api.js",
  "./admin.js",
  "./franchise.js",

  "./journal.js",
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
  if (url.origin !== self.location.origin) {
    return;
  }

  const isData = ["/games.json", "/history.json"]
    .some((ending) => url.pathname.endsWith(ending));
  const isCover = url.pathname.includes("/assets/covers/");

  if (isData) {
    event.respondWith((async () => {
      const canonicalUrl = new URL(event.request.url);
      canonicalUrl.search = "";
      const cacheKey = new Request(canonicalUrl.toString());
      try {
        const response = await fetch(event.request);
        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(cacheKey, response.clone());
        }
        return response;
      } catch {
        return (await caches.match(cacheKey)) || Response.error();
      }
    })());
    return;
  }

  if (isCover) {
    event.respondWith((async () => {
      const cached = await caches.match(event.request);
      if (cached) return cached;
      try {
        const response = await fetch(event.request);
        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(event.request, response.clone());
        }
        return response;
      } catch {
        return (await caches.match("./placeholders/game-placeholder.svg")) || Response.error();
      }
    })());
    return;
  }

  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    if (cached) return cached;
    try {
      return await fetch(event.request);
    } catch {
      if (event.request.mode === "navigate") {
        return (await caches.match("./index.html")) || Response.error();
      }
      return Response.error();
    }
  })());
});
