// Previous stable cache: ludograph-v5-5-3-mobile-franchise-stability
// Previous stable cache: ludograph-v5-5-2-home-topbar-fidelity
// Previous stable cache: ludograph-v5-5-1-home-fidelity
// Previous stable cache: ludograph-v5-5-full-interface-rebuild
// Previous stable cache: ludograph-v5-4-complete-visual-overhaul
// Previous stable cache: ludograph-v5-3-9-franchise-page-stability

// Previous stable cache: ludograph-v5-3-rebrand-platform-identity
// Previous stable cache: the-free-vault-v4-7-6-auth-callback-recovery
// Previous stable cache: the-free-vault-v4-7-5-candidate-first-search
// Previous stable cache: the-free-vault-v4-7-4-catalog-search-performance
// Previous stable cache: the-free-vault-v4-7-3-metadata-and-admin-loading
// Earlier stable cache: the-free-vault-v4-7-2-editorial-steam-metadata
// Earlier stable cache: the-free-vault-v4-7-1-franchise-bulk-selection
// Earlier stable cache: the-free-vault-v4-7-personal-recommendations
// Earlier stable cache: the-free-vault-v4-6-franchises-editorial
// Earlier stable cache: the-free-vault-v4-5-1-progress-rating-hotfix
// Previous stable cache: the-free-vault-v4-7-9-self-hosted-cutover
const CACHE_NAME = "ludograph-v5-5-5-profile-hero-fidelity";
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./visual-overhaul.css",
  "./interface-rebuild.css",
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
  "./icons/brand/ludograph-mark-64.png",
  "./icons/brand/ludograph-mark-128.png",
  "./icons/stores/steam.png",
  "./icons/stores/epic.png",
  "./icons/stores/playstation.png",
  "./icons/stores/xbox.png",
  "./icons/stores/gog.png",
  "./icons/stores/nintendo.png",
  "./icons/platforms/playstation.png",
  "./icons/platforms/xbox.png",
  "./icons/platforms/nintendo.png",
  "./icons/platforms/windows.png",
  "./icons/platforms/apple.png",
  "./icons/platforms/linux.png",
  "./icons/platforms/sega.png",
  "./icons/platforms/pc.png",
  "./icons/platforms/mobile.png",
  "./icons/platforms/arcade.png",
  "./icons/platforms/retro.png",
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
