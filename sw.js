// Service worker for the browser front end: the page, the engine and the icons are cached, so the page
// works offline once loaded. Bump VERSION when any of the files change.
const VERSION = "cranked-6";
const FILES = ["./", "index.html", "engine.js", "worker.js", "audio-worklet.js", "zip.js", "cranked.js", "cranked.wasm", "manifest.webmanifest", "icon-192.png", "icon-512.png"];
self.addEventListener("install", e => e.waitUntil(caches.open(VERSION).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(keys =>
  Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request)));
});
