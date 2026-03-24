/* PWA mínimo: evita 404 en despliegue; sin caché agresiva (sesión Supabase / datos en vivo). */
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
