// sw.js - 知微工作台 PWA
// 关键策略：HTML（./、./index.html）永远走网络（network-first），只在离线时回退缓存；
// 静态资源（图标/manifest）走缓存优先。这样发版后用户刷新即见最新版，无需手动清缓存。
const CACHE = 'zhiwei-mobile-v3';
const STATIC = [
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(STATIC)));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

function isHtml(url){
  const p = url.pathname;
  return p === '/' || p.endsWith('/') || p.endsWith('index.html');
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  const url = new URL(req.url);

  // HTML：network-first —— 永远优先拿最新版，离线才用缓存
  if (isHtml(url)) {
    e.respondWith(
      fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // 静态资源：cache-first，后台静默更新
  e.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
});
