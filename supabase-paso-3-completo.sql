-- ============================================================
-- PASO 3 COMPLETO (despliegue Supabase)
-- Ejecutar TODO este archivo en Supabase → SQL Editor → Run
-- Prerrequisito: supabase-schema.sql (y helpers RLS como is_super_admin,
-- my_empresa_id, empresa_activa — p. ej. supabase-production-hardening.sql)
--
-- Contiene en orden:
--   1) supabase-fix-crear-empresa-y-grants.sql  (idempotente; repetir es seguro)
--   2) supabase-super-admin-user-tools.sql      (RPC panel super-admin)
--   3) supabase-pos-sync.sql                    (tabla pos_workspace_state + Realtime)
--
-- Mantén también los tres .sql por separado en el repo para aplicar solo uno.
-- ============================================================


-- ##############################
-- PARTE 1/3: crear_empresa + columnas + grants
-- ##############################

-- Empresas: columnas que el panel y la RPC esperan
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS plan text DEFAULT 'basico';
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS moneda text DEFAULT 'Q';
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS telefono text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS direccion text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS email_contacto text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS codigo_acceso text;

-- Perfiles: el POS comprueba activo; en esquemas viejos puede faltar
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.crear_empresa(
  p_nombre            text,
  p_moneda            text DEFAULT 'Q',
  p_fecha_vencimiento date DEFAULT NULL,
  p_plan              text DEFAULT 'basico',
  p_codigo_acceso     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empresa_id uuid;
  v_moneda     text;
  v_plan       text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  v_moneda := COALESCE(NULLIF(trim(p_moneda), ''), 'Q');
  v_plan   := COALESCE(NULLIF(trim(p_plan), ''), 'basico');

  INSERT INTO public.empresas (nombre, moneda, fecha_vencimiento, plan)
  VALUES (trim(p_nombre), v_moneda, p_fecha_vencimiento, v_plan)
  RETURNING id INTO v_empresa_id;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'config_empresa'
  ) THEN
    INSERT INTO public.config_empresa (empresa_id, moneda)
    VALUES (v_empresa_id, v_moneda)
    ON CONFLICT (empresa_id) DO NOTHING;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'mesas'
  ) THEN
    INSERT INTO public.mesas (empresa_id, nombre, area)
    SELECT v_empresa_id, 'Mesa ' || gs, 'general'
    FROM generate_series(1, 20) gs;
    INSERT INTO public.mesas (empresa_id, nombre, area)
    SELECT v_empresa_id, 'VIP ' || chr(64 + gs), 'vip'
    FROM generate_series(1, 3) gs;
    INSERT INTO public.mesas (empresa_id, nombre, area)
    SELECT v_empresa_id, 'Barra ' || gs, 'bar'
    FROM generate_series(1, 15) gs;
    INSERT INTO public.mesas (empresa_id, nombre, area)
    VALUES (v_empresa_id, 'Gerencial', 'ger');
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'categorias'
  ) THEN
    INSERT INTO public.categorias (empresa_id, nombre, orden) VALUES
      (v_empresa_id, 'Entradas',          1),
      (v_empresa_id, 'Sopas',             2),
      (v_empresa_id, 'Ensaladas',         3),
      (v_empresa_id, 'Platillos fuertes', 4),
      (v_empresa_id, 'Postres',           5),
      (v_empresa_id, 'Bebidas',           6);
  END IF;

  RETURN v_empresa_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_empresa(text, text, date, text, text) TO authenticated;


-- ##############################
-- PARTE 2/3: herramientas Super Admin (emails + asignar empresa)
-- ##############################

CREATE OR REPLACE FUNCTION public.super_admin_list_users_with_email()
RETURNS TABLE (
  profile_id uuid,
  email text,
  role public.app_role,
  nombre_visible text,
  activo boolean,
  empresa_id uuid,
  empresa_nombre text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  RETURN QUERY
  SELECT
    p.id,
    u.email::text,
    p.role,
    p.nombre_visible,
    p.activo,
    p.empresa_id,
    e.nombre,
    p.created_at
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  LEFT JOIN public.empresas e ON e.id = p.empresa_id
  ORDER BY p.created_at DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.super_admin_assign_empresa(uuid, uuid, public.app_role);

CREATE OR REPLACE FUNCTION public.super_admin_assign_empresa(
  p_user_id uuid,
  p_empresa_id uuid,
  p_role text DEFAULT 'staff'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role public.app_role;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  IF lower(trim(p_role)) NOT IN ('staff', 'empresa_admin', 'super_admin') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_role;
  END IF;
  v_role := lower(trim(p_role))::public.app_role;
  IF v_role = 'super_admin' AND p_empresa_id IS NOT NULL THEN
    RAISE EXCEPTION 'super_admin no debe tener empresa asignada';
  END IF;
  UPDATE public.profiles
  SET empresa_id = CASE WHEN v_role = 'super_admin' THEN NULL ELSE p_empresa_id END,
      role = v_role
  WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_list_users_with_email() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.super_admin_assign_empresa(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_list_users_with_email() TO authenticated;
GRANT EXECUTE ON FUNCTION public.super_admin_assign_empresa(uuid, uuid, text) TO authenticated;


-- ##############################
-- PARTE 3/3: sincronización POS en la nube (pos_workspace_state)
-- ##############################

CREATE TABLE IF NOT EXISTS public.pos_workspace_state (
  empresa_id   uuid PRIMARY KEY REFERENCES public.empresas(id) ON DELETE CASCADE,
  payload      jsonb NOT NULL DEFAULT '{}',
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_pos_workspace_updated ON public.pos_workspace_state (updated_at DESC);

ALTER TABLE public.pos_workspace_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pos_workspace_empresa_all" ON public.pos_workspace_state;
CREATE POLICY "pos_workspace_empresa_all"
  ON public.pos_workspace_state FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "pos_workspace_super_admin" ON public.pos_workspace_state;
CREATE POLICY "pos_workspace_super_admin"
  ON public.pos_workspace_state FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_workspace_state'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pos_workspace_state;
  END IF;
END $$;
