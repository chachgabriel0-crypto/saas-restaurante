-- ============================================================
-- Código corto por empresa para login POS (sin correo real)
-- Ejecutar en Supabase → SQL Editor
--
-- Supabase Auth sigue usando "email" internamente; el POS arma:
--   {codigo}.{usuario}@pos-login.invalid
-- El código es único por restaurante → no hay choque "maria" entre empresas.
-- ============================================================

ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS codigo_acceso text;

DROP INDEX IF EXISTS idx_empresas_codigo_acceso_lower;
CREATE UNIQUE INDEX idx_empresas_codigo_acceso_lower
  ON public.empresas (lower(trim(codigo_acceso)))
  WHERE codigo_acceso IS NOT NULL AND btrim(codigo_acceso) <> '';

-- Ampliar RPC (5º parámetro opcional; llamadas viejas siguen funcionando)
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
  v_codigo     text;
  v_base       text;
  v_try        text;
  v_n          int := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  v_codigo := nullif(
    lower(regexp_replace(trim(coalesce(p_codigo_acceso, '')), '[^a-zA-Z0-9]+', '', 'g')),
    ''
  );

  IF v_codigo IS NULL THEN
    SELECT string_agg(substr(trim(w), 1, 1), '')
    INTO v_base
    FROM unnest(string_to_array(trim(p_nombre), ' ')) AS t(w)
    WHERE trim(t.w) <> '';

    v_codigo := nullif(
      lower(regexp_replace(coalesce(v_base, ''), '[^a-z0-9]+', '', 'g')),
      ''
    );
  END IF;

  IF v_codigo IS NULL OR v_codigo = '' THEN
    v_codigo := 'e';
  END IF;

  IF length(v_codigo) > 12 THEN
    v_codigo := left(v_codigo, 12);
  END IF;

  v_try := v_codigo;
  LOOP
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.empresas e
      WHERE e.codigo_acceso IS NOT NULL
        AND lower(trim(e.codigo_acceso)) = lower(trim(v_try))
    );
    v_n := v_n + 1;
    v_try := v_codigo || v_n::text;
    IF v_n > 9999 THEN
      v_try := 'x' || substr(md5(random()::text || clock_timestamp()::text), 1, 10);
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.empresas e
        WHERE e.codigo_acceso IS NOT NULL
          AND lower(trim(e.codigo_acceso)) = lower(trim(v_try))
      );
      RAISE EXCEPTION 'No se pudo generar codigo_acceso único';
    END IF;
  END LOOP;
  v_codigo := v_try;

  INSERT INTO public.empresas (nombre, moneda, fecha_vencimiento, plan, codigo_acceso)
  VALUES (p_nombre, p_moneda, p_fecha_vencimiento, p_plan, v_codigo)
  RETURNING id INTO v_empresa_id;

  INSERT INTO public.config_empresa (empresa_id, moneda)
  VALUES (v_empresa_id, p_moneda);

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

  INSERT INTO public.categorias (empresa_id, nombre, orden) VALUES
    (v_empresa_id, 'Entradas',         1),
    (v_empresa_id, 'Sopas',            2),
    (v_empresa_id, 'Ensaladas',        3),
    (v_empresa_id, 'Platillos fuertes', 4),
    (v_empresa_id, 'Postres',          5),
    (v_empresa_id, 'Bebidas',          6);

  RETURN v_empresa_id;
END;
$$;
