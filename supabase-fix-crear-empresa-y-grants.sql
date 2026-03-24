-- ============================================================
-- ARREGLO: crear empresa desde Super Admin + vincular usuarios
-- Ejecutar UNA VEZ en Supabase → SQL Editor si fallaba:
--   - "Crear empresa" (RPC crear_empresa)
--   - Asignar restaurante (si faltaba columna activo en profiles, etc.)
--
-- Causas típicas:
--   1) Proyecto creado solo con supabase-super-admin.sql → faltan columnas
--      plan/moneda en empresas y/o tablas mesas, categorias, config_empresa.
--   2) Sin GRANT EXECUTE, PostgREST no deja llamar crear_empresa como usuario autenticado.
-- ============================================================

-- Empresas: columnas que el panel y la RPC esperan
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS plan text DEFAULT 'basico';
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS moneda text DEFAULT 'Q';
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS telefono text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS direccion text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS email_contacto text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS codigo_acceso text;

-- Perfiles: el POS comprueba activo; en esquemas viejos puede faltar
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;

-- RPC: crea la empresa siempre; solo rellena mesas/categorías/config si esas tablas existen
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

-- Permisos para que el Super Admin (rol authenticated) pueda invocar la RPC
GRANT EXECUTE ON FUNCTION public.crear_empresa(text, text, date, text, text) TO authenticated;
