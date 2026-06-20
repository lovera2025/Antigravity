-- =========================================================================
-- CIERRE DE CAJA OPERATIVO — guía de cambio + anotaciones PDF
-- Ejecutar en Supabase SQL Editor antes del deploy (fecha corte 2026-06-18).
-- Espejo SQLite v47: cierre_caja_guia_movimientos, cierre_caja_anotaciones
-- SyncEngine: pull incremental + cola _sync_queue (mismo flujo manual).
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.cierre_caja_guia_movimientos (
  id UUID PRIMARY KEY,
  fecha DATE NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('reposicion', 'uso', 'ajuste')),
  monto NUMERIC(14, 2) NOT NULL CHECK (monto >= 0),
  saldo_antes NUMERIC(14, 2),
  saldo_despues NUMERIC(14, 2) NOT NULL CHECK (saldo_despues >= 0),
  nota TEXT,
  fecha_mov TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_guia_cambio_fecha
  ON public.cierre_caja_guia_movimientos(fecha DESC, fecha_mov DESC);
CREATE INDEX IF NOT EXISTS idx_guia_cambio_updated
  ON public.cierre_caja_guia_movimientos(updated_at DESC);

CREATE TABLE IF NOT EXISTS public.cierre_caja_anotaciones (
  id UUID PRIMARY KEY,
  fecha DATE NOT NULL,
  turno TEXT NOT NULL CHECK (turno IN ('manana', 'tarde', 'dia')),
  texto TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (fecha, turno)
);

CREATE INDEX IF NOT EXISTS idx_cierre_anotacion_fecha
  ON public.cierre_caja_anotaciones(fecha DESC, turno);
CREATE INDEX IF NOT EXISTS idx_cierre_anotacion_updated
  ON public.cierre_caja_anotaciones(updated_at DESC);

ALTER TABLE public.cierre_caja_guia_movimientos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cierre_caja_anotaciones ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'cierre_caja_guia_mov_all_authenticated'
      AND tablename = 'cierre_caja_guia_movimientos'
  ) THEN
    CREATE POLICY "cierre_caja_guia_mov_all_authenticated"
      ON public.cierre_caja_guia_movimientos
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'cierre_caja_anotaciones_all_authenticated'
      AND tablename = 'cierre_caja_anotaciones'
  ) THEN
    CREATE POLICY "cierre_caja_anotaciones_all_authenticated"
      ON public.cierre_caja_anotaciones
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;
