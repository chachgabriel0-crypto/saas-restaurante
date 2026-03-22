-- ============================================================
-- SaaS Restaurante — Esquema Super Admin + empresas (Supabase)
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query → Run
-- ============================================================

-- 1) Tipos
CREATE TYPE public.empresa_estado AS ENUM ('activa', 'suspendida');

-- 2) Tabla empresas
CREATE TABLE public.empresas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL,
  logo_url text,
  estado public.empresa_estado NOT NULL DEFAULT 'activa',
  fecha_vencimiento date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_empresas_estado ON public.empresas (estado);
CREATE INDEX idx_empresas_vencimiento ON public.empresas (fecha_vencimiento);

-- 3) Perfiles (1 fila por usuario de auth.users)
CREATE TYPE public.app_role AS ENUM ('super_admin', 'empresa_admin', 'staff');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  empresa_id uuid REFERENCES public.empresas (id) ON DELETE SET NULL,
  role public.app_role NOT NULL DEFAULT 'staff',
  nombre_visible text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_empresa ON public.profiles (empresa_id);

-- 4) Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_empresas_updated
  BEFORE UPDATE ON public.empresas
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER trg_profiles_updated
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- 5) Helpers para RLS
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'super_admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.my_empresa_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  (SELECT empresa_id FROM public.profiles WHERE id = auth.uid() LIMIT 1);
$$;

-- 6) RLS
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- empresas: super_admin todo; usuarios de empresa solo leen la suya (para validar estado en app)
CREATE POLICY "empresas_super_admin_all"
  ON public.empresas
  FOR ALL
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE POLICY "empresas_read_own"
  ON public.empresas
  FOR SELECT
  TO authenticated
  USING (
    NOT public.is_super_admin()
    AND id = public.my_empresa_id()
  );

-- profiles: cada uno lee/actualiza el propio; super_admin lee todos (para administración)
CREATE POLICY "profiles_self_select"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid() OR public.is_super_admin());

CREATE POLICY "profiles_self_update"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_super_admin_update_all"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE POLICY "profiles_super_insert"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_super_admin());

-- Solo super_admin puede cambiar rol o empresa_id (evita auto-ascenso a super_admin)
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.role IS DISTINCT FROM OLD.role OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id THEN
      IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Solo un super administrador puede cambiar rol o empresa';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_protect
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.protect_profile_privileged_fields();

-- 7) Nueva cuenta: crear fila en profiles al registrarse (rol por defecto staff; tú cambias a super_admin una vez)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, role)
  VALUES (NEW.id, 'staff');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 8) (Opcional) Primera empresa de ejemplo — borra o adapta
-- INSERT INTO public.empresas (nombre, estado, fecha_vencimiento)
-- VALUES ('Demo', 'activa', (CURRENT_DATE + interval '30 days')::date);

-- ============================================================
-- 9) Storage: bucket para logos (ejecutar después del resto)
--    También puedes crear el bucket en UI: Storage → New bucket → name: logos-empresas
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'logos-empresas',
  'logos-empresas',
  true,
  5242880,
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif']::text[]
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "logos_super_admin_rw"
  ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'logos-empresas'
    AND public.is_super_admin()
  )
  WITH CHECK (
    bucket_id = 'logos-empresas'
    AND public.is_super_admin()
  );

CREATE POLICY "logos_public_read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'logos-empresas');

-- ============================================================
-- DESPUÉS de ejecutar lo anterior:
-- 1) Regístrate en Authentication → Users (Sign up desde tu app o "Add user").
-- 2) En Table Editor → profiles, localiza tu usuario y pon role = super_admin.
-- 3) Si creaste el bucket en la UI y falla el INSERT duplicado, ignora o comenta el bloque 9.
-- ============================================================
