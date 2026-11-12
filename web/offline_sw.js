// EventFriend offline service worker.
// Bewaart alle app-bestanden, zodat de webversie (en de calculators)
// ook zonder internet werkt. Online haalt hij altijd eerst de nieuwste versie.
'use strict';

const CACHE = 'eventfriend-v2';
const CORE = ['./', 'index.html', 'flutter_bootstrap.js', 'manifest.json',
  'favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    let files = [];
    try {
      const res = await fetch('precache_manifest.json', { cache: 'no-store' });
      const manifest = await res.json();
      files = manifest.entries.map((e) => e.url);
    } catch (e) {
      console.warn('Precache manifest niet gevonden', e);
    }
    const all = [...new Set([...CORE, ...files])];
    await Promise.all(all.map(async (url) => {
      try { await cache.add(new Request(url, { cache: 'reload' })); }
      catch (e) { console.warn('Niet gecachet:', url); }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // agenda's e.d. niet cachen

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const res = await fetch(req);
      if (res.ok) cache.put(req, res.clone());
      return res;
    } catch (e) {
      const hit = await cache.match(req, { ignoreSearch: true });
      if (hit) return hit;
      if (req.mode === 'navigate') {
        const index = await cache.match('index.html');
        if (index) return index;
      }
      throw e;
    }
  })());
});
