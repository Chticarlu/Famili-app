const C='famili-v5-16-offline-shell-refresh';
const A=['/','/index.html','/manifest.webmanifest','/icon-192.png','/icon-512.png'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(C).then(cache=>cache.addAll(A)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==C).map(k=>caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET') return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin) return;

  if(req.mode==='navigate'){
    event.respondWith(
      fetch(req)
        .then(async res=>{
          // Persist only the public shell, never recovery or checkout URLs.
          if(res.ok && !url.search && (url.pathname==='/' || url.pathname==='/index.html')){
            try{
              const cache=await caches.open(C);
              await cache.put('/index.html',res.clone());
            }catch(_){ /* A storage failure must not block online navigation. */ }
          }
          return res;
        })
        .catch(()=>caches.match('/index.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached=>{
      const network=fetch(req).then(res=>{
        if(res && res.ok){
          const clone=res.clone();
          caches.open(C).then(cache=>cache.put(req,clone));
        }
        return res;
      }).catch(()=>cached);
      return cached || network;
    })
  );
});
