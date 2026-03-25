-- ============================================================
-- REINICIO COMPLETO — SaaS Resta (solo objetos de ESTA app en public + storage logos)
-- Supabase → SQL Editor → UNA sola consulta → Run
--
-- Qué hace:
--   - Quita pos_workspace_state de Realtime (si estaba)
--   - Borra vistas, tablas de negocio, funciones y ENUMs de este proyecto
--   - Borra políticas del bucket logos-empresas (el bucket en sí NO se borra)
--
-- NO borra: auth.users (tus cuentas de login siguen en Authentication).
-- Después de reconstruir el esquema, vuelve a crear filas en public.profiles
-- (ver nota al final de este archivo).
--
-- Después de ejecutar ESTE script, en orden:
--   1) supabase-schema.sql          (todo el archivo)
--   2) supabase-production-hardening.sql
--   3) supabase-paso-3-completo.sql
--   4) fix-super-admin-by-email.sql (edita tu correo)
--   5) Opcional: sincronizar perfiles con usuarios ya existentes (bloque abajo)
-- ============================================================

-- 1) Realtime
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_workspace_state'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.pos_workspace_state;
  END IF;
END $$;

-- 2) Vistas (dependen de tablas)
DROP VIEW IF EXISTS public.v_empresas_resumen CASCADE;
DROP VIEW IF EXISTS public.v_ventas_mes CASCADE;

-- 3) Tablas de la app (orden en una sola sentencia: PostgreSQL resuelve dependencias)
DROP TABLE IF EXISTS
  public.pos_workspace_state,
  public.orden_items,
  public.ventas,
  public.ordenes,
  public.productos,
  public.categorias,
  public.mesas,
  public.egresos,
  public.auditoria,
  public.config_empresa,
  public.profiles,
  public.empresas
CASCADE;

-- 4) Trigger en auth (si quedó huérfano, fallaría al recrear el esquema)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 5) Funciones de la app (CASCADE por si quedan triggers enlazados)
-- crear_empresa: pueden quedar DOS firmas (4 y 5 args); borrar ambas antes de reconstruir
DROP FUNCTION IF EXISTS public.crear_empresa(text, text, date, text) CASCADE;
DROP FUNCTION IF EXISTS public.crear_empresa(text, text, date, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.super_admin_list_users_with_email() CASCADE;
DROP FUNCTION IF EXISTS public.super_admin_assign_empresa(uuid, uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.super_admin_assign_empresa(uuid, uuid, public.app_role) CASCADE;
DROP FUNCTION IF EXISTS public.super_admin_dashboard_stats() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.protect_profile_privileged_fields() CASCADE;
DROP FUNCTION IF EXISTS public.empresa_activa() CASCADE;
DROP FUNCTION IF EXISTS public.my_role() CASCADE;
DROP FUNCTION IF EXISTS public.my_empresa_id() CASCADE;
DROP FUNCTION IF EXISTS public.is_super_admin() CASCADE;
DROP FUNCTION IF EXISTS public.set_updated_at() CASCADE;

-- 6) Tipos ENUM del proyecto
DROP TYPE IF EXISTS public.table_status CASCADE;
DROP TYPE IF EXISTS public.payment_method CASCADE;
DROP TYPE IF EXISTS public.order_status CASCADE;
DROP TYPE IF EXISTS public.app_role CASCADE;
DROP TYPE IF EXISTS public.empresa_estado CASCADE;

-- 7) Políticas de Storage del bucket de logos (supabase-schema las vuelve a crear)
DROP POLICY IF EXISTS "logos_super_admin_rw" ON storage.objects;
DROP POLICY IF EXISTS "logos_empresa_admin_upload" ON storage.objects;
DROP POLICY IF EXISTS "logos_empresa_admin_update_own" ON storage.objects;
DROP POLICY IF EXISTS "logos_empresa_admin_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "logos_public_read" ON storage.objects;

-- Listo. Siguiente: pegar supabase-schema.sql → hardening → paso-3 → fix super_admin.

-- ============================================================
-- PASO OPCIONAL (después de reconstruir todo el esquema con los 3 SQL):
-- Tus usuarios en Authentication siguen existiendo pero sin fila en profiles.
-- Ejecuta UNA VEZ esto para recrear el perfil base (rol staff):
--
-- INSERT INTO public.profiles (id, role)
-- SELECT id, 'staff'::public.app_role FROM auth.users
-- ON CONFLICT (id) DO NOTHING;
--
-- Luego ejecuta fix-super-admin-by-email.sql con tu correo para ser super_admin.
-- ============================================================
