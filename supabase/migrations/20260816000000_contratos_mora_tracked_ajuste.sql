-- Perdón / poner mora en ficha durable al replay post-pull.
-- Requerido por app SQLite v68 + sync_engine (mora_tracked_ajuste).
ALTER TABLE public.contratos_alumnos
  ADD COLUMN IF NOT EXISTS mora_tracked_ajuste DOUBLE PRECISION DEFAULT 0;

COMMENT ON COLUMN public.contratos_alumnos.mora_tracked_ajuste IS
  'Delta admin sobre el replay del historial. Tracked efectivo = max(0, objetivo + ajuste). Negativo = perdón de ficha.';
