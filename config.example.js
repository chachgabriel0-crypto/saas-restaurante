/**
 * Copia este archivo como `config.js` en la misma carpeta que index.html / super-admin.html
 * y reemplaza URL y anon key (Supabase → Settings → API → anon public).
 *
 * Seguridad producción:
 * - Nunca subas `config.js` con claves reales a un repo público (ya está en .gitignore).
 * - La anon key en el frontend es normal; la seguridad real está en RLS de Supabase.
 * - No uses nunca la service_role key en el navegador.
 */
window.RESTAURANTE_CONFIG = {
  supabaseUrl: 'https://TU_PROYECTO.supabase.co',
  supabaseAnonKey: 'TU_ANON_KEY'
};
