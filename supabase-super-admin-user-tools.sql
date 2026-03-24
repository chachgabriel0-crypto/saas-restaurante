-- ============================================================
-- Herramientas Super Admin: emails Auth + asignar empresa
-- Ejecutar en Supabase → SQL Editor (mismo proyecto que el POS)
-- Requiere haber aplicado antes supabase-schema.sql (tablas + RLS)
-- ============================================================

-- Lista perfiles con email de auth.users (solo super_admin)
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

-- Asignar empresa y rol a un usuario (solo super_admin)
-- Tercer argumento en TEXT para que PostgREST/JS lo resuelva sin fricción con el enum.
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
