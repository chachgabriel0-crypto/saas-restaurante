/**
 * Copia este archivo como `config.js` en la misma carpeta que index.html / super-admin.html
 * y reemplaza URL y anon key (Supabase → Settings → API → anon public).
 *
 * Despliegue simple: sube la carpeta completa con `config.js` y la carpeta `vendor/`
 * (archivo `vendor/supabase.umd.js`). No hace falta `npm run build`.
 *
 * Seguridad: la anon key en el frontend es normal; RLS en Supabase protege los datos.
 * No uses la service_role en el navegador. Si el repo en GitHub es público, no subas claves reales.
 */
window.RESTAURANTE_CONFIG = {
  supabaseUrl: 'https://TU_PROYECTO.supabase.co',
  supabaseAnonKey: 'TU_ANON_KEY'
};
