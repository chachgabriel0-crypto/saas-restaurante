-- ============================================================
-- SaaS Restaurante POS — Esquema COMPLETO Multi-Tenant
-- Compatible con Supabase (PostgreSQL)
-- INSTRUCCIONES: Ir a Supabase → SQL Editor → New query → Pegar TODO esto → Run
-- ============================================================

-- ============================================================
-- 0) EXTENSIONES
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1) TIPOS ENUM
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.empresa_estado AS ENUM ('activa', 'suspendida');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('super_admin', 'empresa_admin', 'staff');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.order_status AS ENUM ('pending', 'cooking', 'ready', 'delivered', 'paid', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.table_status AS ENUM ('free', 'busy', 'reserved');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2) TABLA: empresas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.empresas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            text NOT NULL,
  logo_url          text,
  estado            public.empresa_estado NOT NULL DEFAULT 'activa',
  fecha_vencimiento date,
  plan              text DEFAULT 'basico',   -- basico | pro | enterprise
  moneda            text DEFAULT 'Q',
  telefono          text,
  direccion         text,
  email_contacto    text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_empresas_estado       ON public.empresas (estado);
CREATE INDEX IF NOT EXISTS idx_empresas_vencimiento  ON public.empresas (fecha_vencimiento);

-- ============================================================
-- 3) TABLA: profiles (1 fila por usuario de auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id              uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  empresa_id      uuid REFERENCES public.empresas (id) ON DELETE SET NULL,
  role            public.app_role NOT NULL DEFAULT 'staff',
  nombre_visible  text,
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_empresa ON public.profiles (empresa_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role    ON public.profiles (role);

-- ============================================================
-- 4) TABLA: mesas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.mesas (
  id          uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid    NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  nombre      text    NOT NULL,
  area        text    NOT NULL DEFAULT 'general',  -- general | vip | bar | ger
  estado      public.table_status NOT NULL DEFAULT 'free',
  capacidad   int     DEFAULT 4,
  activa      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mesas_empresa ON public.mesas (empresa_id);
CREATE INDEX IF NOT EXISTS idx_mesas_estado  ON public.mesas (estado);

-- ============================================================
-- 5) TABLA: categorias (categorías del menú)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.categorias (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  nombre      text NOT NULL,
  orden       int  DEFAULT 0,
  activa      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_categorias_empresa ON public.categorias (empresa_id);

-- ============================================================
-- 6) TABLA: productos
-- ============================================================
CREATE TABLE IF NOT EXISTS public.productos (
  id           uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid    NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  categoria_id uuid    REFERENCES public.categorias (id) ON DELETE SET NULL,
  nombre       text    NOT NULL,
  descripcion  text,
  precio       numeric(10,2) NOT NULL DEFAULT 0,
  foto_url     text,
  disponible   boolean NOT NULL DEFAULT true,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_productos_empresa   ON public.productos (empresa_id);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON public.productos (categoria_id);
CREATE INDEX IF NOT EXISTS idx_productos_disponible ON public.productos (empresa_id, disponible);

-- ============================================================
-- 7) TABLA: ordenes
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ordenes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      uuid NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  mesa_id         uuid REFERENCES public.mesas (id) ON DELETE SET NULL,
  vendedor_id     uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  nombre_cliente  text,
  estado          public.order_status NOT NULL DEFAULT 'pending',
  notas           text,
  subtotal        numeric(10,2) NOT NULL DEFAULT 0,
  descuento       numeric(10,2) NOT NULL DEFAULT 0,
  total           numeric(10,2) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ordenes_empresa    ON public.ordenes (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_mesa       ON public.ordenes (mesa_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_estado     ON public.ordenes (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_ordenes_vendedor   ON public.ordenes (vendedor_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_fecha      ON public.ordenes (empresa_id, created_at DESC);

-- ============================================================
-- 8) TABLA: orden_items (detalle de cada orden)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.orden_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  orden_id     uuid NOT NULL REFERENCES public.ordenes (id) ON DELETE CASCADE,
  producto_id  uuid REFERENCES public.productos (id) ON DELETE SET NULL,
  nombre       text NOT NULL,  -- snapshot del nombre al momento de la orden
  precio       numeric(10,2) NOT NULL,
  cantidad     int  NOT NULL DEFAULT 1,
  estado_item  text NOT NULL DEFAULT 'pending',  -- pending | cooking | ready | delivered
  notas        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orden_items_orden   ON public.orden_items (orden_id);
CREATE INDEX IF NOT EXISTS idx_orden_items_empresa ON public.orden_items (empresa_id);

-- ============================================================
-- 9) TABLA: ventas (registro de cobros)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ventas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  orden_id       uuid REFERENCES public.ordenes (id) ON DELETE SET NULL,
  mesa_id        uuid REFERENCES public.mesas (id) ON DELETE SET NULL,
  vendedor_id    uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  nombre_cliente text,
  subtotal       numeric(10,2) NOT NULL DEFAULT 0,
  descuento      numeric(10,2) NOT NULL DEFAULT 0,
  total          numeric(10,2) NOT NULL DEFAULT 0,
  metodo_pago    public.payment_method NOT NULL DEFAULT 'cash',
  monto_recibido numeric(10,2),
  cambio         numeric(10,2),
  folio          text,  -- número consecutivo por empresa
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ventas_empresa  ON public.ventas (empresa_id);
CREATE INDEX IF NOT EXISTS idx_ventas_fecha    ON public.ventas (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ventas_vendedor ON public.ventas (vendedor_id);
CREATE INDEX IF NOT EXISTS idx_ventas_metodo   ON public.ventas (empresa_id, metodo_pago);

-- ============================================================
-- 10) TABLA: egresos (gastos / expenses)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.egresos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   uuid NOT NULL REFERENCES public.empresas (id) ON DELETE CASCADE,
  registrado_por uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  concepto     text NOT NULL,
  monto        numeric(10,2) NOT NULL,
  categoria    text DEFAULT 'general',
  metodo_pago  public.payment_method DEFAULT 'cash',
  notas        text,
  fecha        date NOT NULL DEFAULT CURRENT_DATE,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_egresos_empresa ON public.egresos (empresa_id);
CREATE INDEX IF NOT EXISTS idx_egresos_fecha   ON public.egresos (empresa_id, fecha DESC);

-- ============================================================
-- 11) TABLA: auditoria (bitácora append-only)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.auditoria (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid REFERENCES public.empresas (id) ON DELETE CASCADE,
  user_id     uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  accion      text NOT NULL,
  detalles    jsonb,
  ip          text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auditoria_empresa ON public.auditoria (empresa_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_user    ON public.auditoria (user_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha   ON public.auditoria (empresa_id, created_at DESC);

-- ============================================================
-- 12) TABLA: config_empresa (configuración por empresa)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.config_empresa (
  empresa_id        uuid PRIMARY KEY REFERENCES public.empresas (id) ON DELETE CASCADE,
  moneda            text    DEFAULT 'Q',
  comision_pos      numeric(5,2) DEFAULT 3.5,
  timeout_sesion    int     DEFAULT 600,   -- segundos
  color_primario    text    DEFAULT '#d66c20',
  tema              text    DEFAULT 'light',
  extras            jsonb   DEFAULT '{}'::jsonb,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 13) FUNCIÓN: updated_at automático
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers updated_at
DO $$ BEGIN
  CREATE TRIGGER trg_empresas_updated   BEFORE UPDATE ON public.empresas    FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TRIGGER trg_profiles_updated   BEFORE UPDATE ON public.profiles    FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TRIGGER trg_mesas_updated      BEFORE UPDATE ON public.mesas       FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TRIGGER trg_productos_updated  BEFORE UPDATE ON public.productos   FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TRIGGER trg_ordenes_updated    BEFORE UPDATE ON public.ordenes     FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TRIGGER trg_ventas_updated     BEFORE UPDATE ON public.config_empresa FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 14) FUNCIONES HELPER para RLS
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'super_admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.my_empresa_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT empresa_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.my_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role::text FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- Verifica si la empresa del usuario actual está activa y no vencida
CREATE OR REPLACE FUNCTION public.empresa_activa()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.empresas e
    JOIN public.profiles p ON p.empresa_id = e.id
    WHERE p.id = auth.uid()
      AND e.estado = 'activa'
      AND (e.fecha_vencimiento IS NULL OR e.fecha_vencimiento >= CURRENT_DATE)
  );
$$;

-- ============================================================
-- 15) ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE public.empresas      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mesas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categorias    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.productos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ordenes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orden_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ventas        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.egresos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.config_empresa ENABLE ROW LEVEL SECURITY;

-- ---- EMPRESAS ----
DROP POLICY IF EXISTS "empresas_super_admin_all" ON public.empresas;
CREATE POLICY "empresas_super_admin_all"
  ON public.empresas FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "empresas_read_own" ON public.empresas;
CREATE POLICY "empresas_read_own"
  ON public.empresas FOR SELECT TO authenticated
  USING (NOT public.is_super_admin() AND id = public.my_empresa_id());

-- ---- PROFILES ----
DROP POLICY IF EXISTS "profiles_select" ON public.profiles;
CREATE POLICY "profiles_select"
  ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_super_admin()
    OR (empresa_id = public.my_empresa_id() AND public.my_role() IN ('empresa_admin','super_admin')));

DROP POLICY IF EXISTS "profiles_self_update" ON public.profiles;
CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles_super_admin_all" ON public.profiles;
CREATE POLICY "profiles_super_admin_all"
  ON public.profiles FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "profiles_empresa_admin_insert" ON public.profiles;
CREATE POLICY "profiles_empresa_admin_insert"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (
    public.my_role() = 'empresa_admin'
    AND empresa_id = public.my_empresa_id()
    AND role = 'staff'
  );

-- ---- HELPER: política multitenant genérica ----
-- Para mesas, categorias, productos, ordenes, orden_items, ventas, egresos:
-- El usuario puede ver/editar solo datos de su propia empresa activa.

-- MESAS
DROP POLICY IF EXISTS "mesas_empresa" ON public.mesas;
CREATE POLICY "mesas_empresa"
  ON public.mesas FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "mesas_super_admin" ON public.mesas;
CREATE POLICY "mesas_super_admin"
  ON public.mesas FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- CATEGORIAS
DROP POLICY IF EXISTS "categorias_empresa" ON public.categorias;
CREATE POLICY "categorias_empresa"
  ON public.categorias FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "categorias_super_admin" ON public.categorias;
CREATE POLICY "categorias_super_admin"
  ON public.categorias FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- PRODUCTOS
DROP POLICY IF EXISTS "productos_empresa" ON public.productos;
CREATE POLICY "productos_empresa"
  ON public.productos FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "productos_super_admin" ON public.productos;
CREATE POLICY "productos_super_admin"
  ON public.productos FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- ORDENES
DROP POLICY IF EXISTS "ordenes_empresa" ON public.ordenes;
CREATE POLICY "ordenes_empresa"
  ON public.ordenes FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "ordenes_super_admin" ON public.ordenes;
CREATE POLICY "ordenes_super_admin"
  ON public.ordenes FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- ORDEN_ITEMS
DROP POLICY IF EXISTS "orden_items_empresa" ON public.orden_items;
CREATE POLICY "orden_items_empresa"
  ON public.orden_items FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "orden_items_super_admin" ON public.orden_items;
CREATE POLICY "orden_items_super_admin"
  ON public.orden_items FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- VENTAS
DROP POLICY IF EXISTS "ventas_empresa" ON public.ventas;
CREATE POLICY "ventas_empresa"
  ON public.ventas FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "ventas_super_admin" ON public.ventas;
CREATE POLICY "ventas_super_admin"
  ON public.ventas FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- EGRESOS
DROP POLICY IF EXISTS "egresos_empresa" ON public.egresos;
CREATE POLICY "egresos_empresa"
  ON public.egresos FOR ALL TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.empresa_activa())
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.empresa_activa());

DROP POLICY IF EXISTS "egresos_super_admin" ON public.egresos;
CREATE POLICY "egresos_super_admin"
  ON public.egresos FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- AUDITORIA
DROP POLICY IF EXISTS "auditoria_empresa_admin" ON public.auditoria;
CREATE POLICY "auditoria_empresa_admin"
  ON public.auditoria FOR SELECT TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.my_role() IN ('empresa_admin','super_admin'));

DROP POLICY IF EXISTS "auditoria_insert" ON public.auditoria;
CREATE POLICY "auditoria_insert"
  ON public.auditoria FOR INSERT TO authenticated
  WITH CHECK (empresa_id = public.my_empresa_id() OR public.is_super_admin());

DROP POLICY IF EXISTS "auditoria_super_admin" ON public.auditoria;
CREATE POLICY "auditoria_super_admin"
  ON public.auditoria FOR SELECT TO authenticated
  USING (public.is_super_admin());

-- CONFIG_EMPRESA
DROP POLICY IF EXISTS "config_empresa_read" ON public.config_empresa;
CREATE POLICY "config_empresa_read"
  ON public.config_empresa FOR SELECT TO authenticated
  USING (empresa_id = public.my_empresa_id());

DROP POLICY IF EXISTS "config_empresa_update" ON public.config_empresa;
CREATE POLICY "config_empresa_update"
  ON public.config_empresa FOR UPDATE TO authenticated
  USING (empresa_id = public.my_empresa_id() AND public.my_role() = 'empresa_admin')
  WITH CHECK (empresa_id = public.my_empresa_id() AND public.my_role() = 'empresa_admin');

DROP POLICY IF EXISTS "config_empresa_super_admin" ON public.config_empresa;
CREATE POLICY "config_empresa_super_admin"
  ON public.config_empresa FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- ============================================================
-- 16) TRIGGER: Protege campos privilegiados de profiles
-- ============================================================
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.role IS DISTINCT FROM OLD.role OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id THEN
      IF NOT public.is_super_admin() AND public.my_role() != 'empresa_admin' THEN
        RAISE EXCEPTION 'Solo un administrador puede cambiar rol o empresa';
      END IF;
      -- empresa_admin solo puede asignar rol 'staff', no super_admin ni empresa_admin
      IF public.my_role() = 'empresa_admin' AND NEW.role != 'staff' THEN
        RAISE EXCEPTION 'El admin de empresa solo puede asignar rol staff';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  CREATE TRIGGER trg_profiles_protect
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE PROCEDURE public.protect_profile_privileged_fields();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 17) TRIGGER: Crear profile automáticamente al registrarse
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, role)
  VALUES (NEW.id, 'staff')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 18) FUNCIÓN: Crear empresa completa (llamada desde super-admin)
-- ============================================================
CREATE OR REPLACE FUNCTION public.crear_empresa(
  p_nombre            text,
  p_moneda            text DEFAULT 'Q',
  p_fecha_vencimiento date DEFAULT NULL,
  p_plan              text DEFAULT 'basico'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_empresa_id uuid;
BEGIN
  -- Solo super_admin puede llamar esta función
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- Insertar empresa
  INSERT INTO public.empresas (nombre, moneda, fecha_vencimiento, plan)
  VALUES (p_nombre, p_moneda, p_fecha_vencimiento, p_plan)
  RETURNING id INTO v_empresa_id;

  -- Crear configuración por defecto
  INSERT INTO public.config_empresa (empresa_id, moneda)
  VALUES (v_empresa_id, p_moneda);

  -- Insertar mesas por defecto (20 generales, 3 VIP, 15 barra, 1 gerencial)
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

  -- Insertar categorías por defecto
  INSERT INTO public.categorias (empresa_id, nombre, orden) VALUES
    (v_empresa_id, 'Entradas',        1),
    (v_empresa_id, 'Sopas',           2),
    (v_empresa_id, 'Ensaladas',       3),
    (v_empresa_id, 'Platillos fuertes', 4),
    (v_empresa_id, 'Postres',         5),
    (v_empresa_id, 'Bebidas',         6);

  RETURN v_empresa_id;
END;
$$;

-- ============================================================
-- 19) STORAGE: Bucket para logos de empresas
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'logos-empresas',
  'logos-empresas',
  true,
  5242880,  -- 5 MB
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
DROP POLICY IF EXISTS "logos_super_admin_rw"  ON storage.objects;
CREATE POLICY "logos_super_admin_rw"
  ON storage.objects FOR ALL TO authenticated
  USING  (bucket_id = 'logos-empresas' AND public.is_super_admin())
  WITH CHECK (bucket_id = 'logos-empresas' AND public.is_super_admin());

DROP POLICY IF EXISTS "logos_empresa_admin_upload" ON storage.objects;
CREATE POLICY "logos_empresa_admin_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'logos-empresas' AND public.my_role() = 'empresa_admin');

DROP POLICY IF EXISTS "logos_public_read" ON storage.objects;
CREATE POLICY "logos_public_read"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'logos-empresas');

-- ============================================================
-- 20) VISTAS ÚTILES
-- ============================================================

-- Resumen de empresas para super admin
CREATE OR REPLACE VIEW public.v_empresas_resumen AS
SELECT
  e.id,
  e.nombre,
  e.logo_url,
  e.estado,
  e.fecha_vencimiento,
  e.plan,
  e.created_at,
  CASE
    WHEN e.estado = 'suspendida' THEN 'suspendida'
    WHEN e.fecha_vencimiento IS NOT NULL AND e.fecha_vencimiento < CURRENT_DATE THEN 'vencida'
    ELSE 'activa'
  END AS estado_real,
  (SELECT COUNT(*) FROM public.profiles p WHERE p.empresa_id = e.id) AS total_usuarios,
  (SELECT COUNT(*) FROM public.mesas m WHERE m.empresa_id = e.id AND m.activa = true) AS total_mesas,
  (SELECT COUNT(*) FROM public.ventas v
   WHERE v.empresa_id = e.id AND v.created_at >= CURRENT_DATE) AS ventas_hoy,
  (SELECT COALESCE(SUM(v.total), 0) FROM public.ventas v
   WHERE v.empresa_id = e.id AND v.created_at >= CURRENT_DATE) AS monto_hoy
FROM public.empresas e;

-- Ventas totales por empresa (mes actual)
CREATE OR REPLACE VIEW public.v_ventas_mes AS
SELECT
  v.empresa_id,
  e.nombre AS empresa,
  DATE_TRUNC('month', v.created_at) AS mes,
  COUNT(*) AS total_transacciones,
  SUM(v.total) AS total_ingresos,
  SUM(CASE WHEN v.metodo_pago = 'cash'     THEN v.total ELSE 0 END) AS efectivo,
  SUM(CASE WHEN v.metodo_pago = 'card'     THEN v.total ELSE 0 END) AS tarjeta,
  SUM(CASE WHEN v.metodo_pago = 'transfer' THEN v.total ELSE 0 END) AS transferencia
FROM public.ventas v
JOIN public.empresas e ON e.id = v.empresa_id
GROUP BY v.empresa_id, e.nombre, DATE_TRUNC('month', v.created_at);

-- ============================================================
-- FIN DEL ESQUEMA
-- ============================================================
-- PASOS SIGUIENTES (después de ejecutar este SQL):
-- 1) Ve a Authentication → Users → "Add user" → crea tu cuenta super admin
-- 2) Ve a Table Editor → profiles → localiza tu usuario → cambia role a 'super_admin'
-- 3) Si falla el bucket de storage por duplicado, ignora ese error o créalo manualmente
--    en Storage → New bucket → nombre: logos-empresas → Public: ON
-- ============================================================
