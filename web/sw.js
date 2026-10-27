// Network-first for the app shell so a push to Pages is picked up; cache is the offline fallback.
const CACHE = "podsnap-v1";
const SHELL = ["./", "index.html", "pricing.html", "styles.css", "app.js", "config.js", "manifest.webmanifest", "icon.svg"];
self.addEventListener("install", (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok && (new URL(req.url).origin === location.origin || /cdn\.jsdelivr|cdnjs|tessdata|fonts\./.test(req.url))) {
        const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy));
      }
      return res;
    }).catch(() => caches.match(req))
  );
});
