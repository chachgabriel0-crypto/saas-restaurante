-- Estado completo del POS por empresa (sincronización entre dispositivos)
-- Ejecutar en Supabase SQL Editor después de supabase-schema.sql

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

-- Realtime (recomendado para ver cambios al instante entre dispositivos):
-- Dashboard → Database → Publications → supabase_realtime → incluir public.pos_workspace_state
-- o Database → Replication según tu versión de Supabase.
