-- =========================================================================
-- CAJA FUERTE — Mi empresa → PERSONAL
-- Movimientos de cupo declarado por el dueño (`asignacion` / `retiro`).
--
-- Ejecutá este script en Supabase SQL Editor si la tabla aún no existe.
-- Espejo SQLite: tabla `caja_fuerte_movimientos` en local_database.dart (v40+).
-- SyncEngine: pull + upsert desde cola `_sync_queue`.
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.caja_fuerte_movimientos (
  id UUID PRIMARY KEY,
  tipo TEXT NOT NULL CHECK (tipo IN ('asignacion', 'retiro')),
  monto NUMERIC(14, 2) NOT NULL CHECK (monto >= 0),
  nota TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_caja_fuerte_mov_created
  ON public.caja_fuerte_movimientos(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_caja_fuerte_mov_tipo
  ON public.caja_fuerte_movimientos(tipo);

ALTER TABLE public.caja_fuerte_movimientos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'caja_fuerte_movimientos_all_authenticated'
      AND tablename = 'caja_fuerte_movimientos'
  ) THEN
    CREATE POLICY "caja_fuerte_movimientos_all_authenticated"
      ON public.caja_fuerte_movimientos
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;
