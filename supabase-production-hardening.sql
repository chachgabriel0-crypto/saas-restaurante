-- ============================================================
-- SaaS Restaurante — Endurecimiento producción (ejecutar DESPUÉS de supabase-schema.sql)
-- Supabase → SQL Editor → Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) Helpers RLS: una sola evaluación de auth.uid() por llamada
--    (reduce trabajo repetido en políticas por fila)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = (SELECT auth.uid()) AND role = 'super_admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.my_empresa_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT empresa_id FROM public.profiles WHERE id = (SELECT auth.uid()) LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.my_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role::text FROM public.profiles WHERE id = (SELECT auth.uid()) LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.empresa_activa()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.empresas e
    JOIN public.profiles p ON p.empresa_id = e.id
    WHERE p.id = (SELECT auth.uid())
      AND e.estado = 'activa'
      AND (e.fecha_vencimiento IS NULL OR e.fecha_vencimiento >= CURRENT_DATE)
  );
$$;

-- ------------------------------------------------------------
-- 2) RPC: dashboard super admin (1 round-trip, menos scans que 4 queries)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.super_admin_dashboard_stats()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_today_start timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC');
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN jsonb_build_object(
    'total_empresas', (SELECT count(*)::int FROM public.empresas),
    'activas', (SELECT count(*)::int FROM public.empresas WHERE estado = 'activa'),
    'suspendidas', (SELECT count(*)::int FROM public.empresas WHERE estado = 'suspendida'),
    'vencidas', (
      SELECT count(*)::int FROM public.empresas e
      WHERE e.estado = 'activa'
        AND e.fecha_vencimiento IS NOT NULL
        AND e.fecha_vencimiento < CURRENT_DATE
    ),
    'ventas_hoy_count', (
      SELECT count(*)::int FROM public.ventas v
      WHERE v.created_at >= v_today_start
    ),
    'ventas_hoy_monto', (
      SELECT COALESCE(sum(v.total), 0)::numeric FROM public.ventas v
      WHERE v.created_at >= v_today_start
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_dashboard_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_dashboard_stats() TO authenticated;

-- ------------------------------------------------------------
-- 3) Índices adicionales (joins / filtros frecuentes)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orden_items_empresa_orden
  ON public.orden_items (empresa_id, orden_id);

CREATE INDEX IF NOT EXISTS idx_profiles_empresa_role
  ON public.profiles (empresa_id, role) WHERE empresa_id IS NOT NULL;

-- ------------------------------------------------------------
-- 4) Vistas: invocador (evita fugas si el owner de la vista es superuser)
--    Requiere PostgreSQL 15+
-- ------------------------------------------------------------
DO $$
BEGIN
  EXECUTE 'ALTER VIEW public.v_empresas_resumen SET (security_invoker = true)';
EXCEPTION WHEN undefined_object THEN NULL;
  WHEN others THEN NULL;
END $$;

DO $$
BEGIN
  EXECUTE 'ALTER VIEW public.v_ventas_mes SET (security_invoker = true)';
EXCEPTION WHEN undefined_object THEN NULL;
  WHEN others THEN NULL;
END $$;

-- ------------------------------------------------------------
-- 5) Revocar acceso directo anon al esquema public (API sigue con JWT + RLS)
-- ------------------------------------------------------------
-- Sin JWT (rol anon) no debe leer tablas de negocio; PostgREST sigue usando authenticated.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- ------------------------------------------------------------
-- 6) Auditoría: impedir borrado y actualización (append-only)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "auditoria_no_update" ON public.auditoria;
CREATE POLICY "auditoria_no_update"
  ON public.auditoria FOR UPDATE TO authenticated
  USING (false);

DROP POLICY IF EXISTS "auditoria_no_delete" ON public.auditoria;
CREATE POLICY "auditoria_no_delete"
  ON public.auditoria FOR DELETE TO authenticated
  USING (false);

-- ------------------------------------------------------------
-- 7) RLS auditoría insert: empresa activa y sin suplantar tenant
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "auditoria_insert" ON public.auditoria;
CREATE POLICY "auditoria_insert"
  ON public.auditoria FOR INSERT TO authenticated
  WITH CHECK (
    (public.is_super_admin())
    OR (
      public.empresa_activa()
      AND empresa_id IS NOT NULL
      AND empresa_id = public.my_empresa_id()
    )
  );

-- ------------------------------------------------------------
-- 8) Storage: logos solo bajo carpeta = uuid de la empresa del admin
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "logos_empresa_admin_upload" ON storage.objects;

CREATE POLICY "logos_empresa_admin_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'logos-empresas'
    AND public.my_role() = 'empresa_admin'
    AND public.empresa_activa()
    AND split_part(name, '/', 1) = public.my_empresa_id()::text
  );

DROP POLICY IF EXISTS "logos_empresa_admin_update_own" ON storage.objects;
CREATE POLICY "logos_empresa_admin_update_own"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'logos-empresas'
    AND public.my_role() = 'empresa_admin'
    AND split_part(name, '/', 1) = public.my_empresa_id()::text
  )
  WITH CHECK (
    bucket_id = 'logos-empresas'
    AND split_part(name, '/', 1) = public.my_empresa_id()::text
  );

DROP POLICY IF EXISTS "logos_empresa_admin_delete_own" ON storage.objects;
CREATE POLICY "logos_empresa_admin_delete_own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'logos-empresas'
    AND public.my_role() = 'empresa_admin'
    AND split_part(name, '/', 1) = public.my_empresa_id()::text
  );

-- Fin
-- ============================================================
