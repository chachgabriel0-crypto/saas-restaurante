/* ============================================================
   SERVICE WORKER — Restaurante POS SaaS
   Estrategia:
   - Cache-first para assets estáticos (HTML, CSS, JS, imágenes)
   - Network-first para llamadas a Supabase API
   ============================================================ */

const CACHE_NAME    = 'restaurante-pos-v3.2.0';
const OFFLINE_URL   = '/offline.html';

// Recursos que se cachean inmediatamente al instalar el SW
const PRECACHE_ASSETS = [
  '/',
  '/index.html',
  '/logo.png',
  '/manifest.webmanifest',
  // Fuentes de Google (si hay conexión al instalar)
  'https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700;800&family=Source+Sans+3:wght@400;500;600;700&display=swap'
];

// Dominios que siempre van a la red (Supabase)
const NETWORK_ONLY_PATTERNS = [
  'supabase.co',
  'supabase.io'
];

// ---- INSTALL ----
self.addEventListener('install', event => {
  console.log('[SW] Instalando versión:', CACHE_NAME);
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        // Precachear assets críticos (ignorar errores individuales)
        return Promise.allSettled(
          PRECACHE_ASSETS.map(url => cache.add(url).catch(e => console.warn('[SW] No se pudo cachear:', url, e)))
        );
      })
      .then(() => self.skipWaiting())
  );
});

// ---- ACTIVATE ----
self.addEventListener('activate', event => {
  console.log('[SW] Activando y limpiando caches antiguas');
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== CACHE_NAME)
            .map(key => {
              console.log('[SW] Eliminando cache antigua:', key);
              return caches.delete(key);
            })
      ))
      .then(() => self.clients.claim())
  );
});

// ---- FETCH ----
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Ignorar requests no-GET y extensiones de navegador
  if (request.method !== 'GET') return;
  if (url.protocol === 'chrome-extension:') return;

  // Supabase y otros APIs: siempre red, sin caché
  const isNetworkOnly = NETWORK_ONLY_PATTERNS.some(p => url.hostname.includes(p));
  if (isNetworkOnly) {
    event.respondWith(
      fetch(request).catch(() => new Response(
        JSON.stringify({ error: 'Sin conexión a internet' }),
        { headers: { 'Content-Type': 'application/json' }, status: 503 }
      ))
    );
    return;
  }

  // Para el HTML principal: Network-first (para obtener actualizaciones),
  // fallback a caché si no hay conexión
  if (request.mode === 'navigate' || url.pathname === '/' || url.pathname.endsWith('.html')) {
    event.respondWith(
      fetch(request)
        .then(response => {
          // Guardar copia fresca en caché
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return response;
        })
        .catch(() => {
          return caches.match(request)
            .then(cached => cached || caches.match('/index.html'));
        })
    );
    return;
  }

  // Para el resto (imágenes, fuentes, etc.): Cache-first
  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;

      return fetch(request).then(response => {
        // Solo cachear respuestas válidas
        if (!response || response.status !== 200 || response.type === 'error') {
          return response;
        }
        const clone = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
        return response;
      });
    })
  );
});

// ---- SYNC (Background Sync) ----
// Para sincronizar datos cuando se recupera la conexión
self.addEventListener('sync', event => {
  if (event.tag === 'sync-ordenes') {
    console.log('[SW] Background sync: ordenes');
    // La app maneja la sincronización desde el cliente
  }
});

// ---- PUSH NOTIFICATIONS (preparado para futuro) ----
self.addEventListener('push', event => {
  const data = event.data?.json() || {};
  const title   = data.title   || 'Restaurante POS';
  const options = {
    body:    data.body    || 'Nueva notificación',
    icon:    '/logo.png',
    badge:   '/logo.png',
    vibrate: [200, 100, 200],
    data:    data.url || '/'
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow(event.notification.data || '/')
  );
});

console.log('[SW] Service Worker registrado — Versión:', CACHE_NAME);
