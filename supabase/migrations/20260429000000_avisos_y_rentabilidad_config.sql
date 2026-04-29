-- =========================================================================
-- Avisos (obligaciones_pago) + Rentabilidad fija (rentabilidad_config)
-- + Backfill de presupuestos.fecha_evento
--
-- Estas tablas existen en SQLite (lib/core/database/local_database.dart) y el
-- SyncEngine ya las pulea/empuja, pero hasta ahora no estaban versionadas
-- en supabase/migrations/. Esta migración cierra el drift entre repo y nube.
--
-- Idempotente: usa CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS y
-- bloques DO $$ para políticas RLS condicionales.
-- =========================================================================

-- 1. OBLIGACIONES DE PAGO (Sistema de Avisos / Vencimientos)
-- Espejo en SQLite: lib/core/database/local_database.dart (CREATE TABLE obligaciones_pago)
-- Columnas serializadas por: lib/models/obligacion_pago.dart (toJson)
CREATE TABLE IF NOT EXISTS public.obligaciones_pago (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo TEXT NOT NULL,
  tipo_obligacion TEXT NOT NULL CHECK (tipo_obligacion IN ('empresa', 'adrian')),
  fecha_vencimiento TIMESTAMPTZ NOT NULL,
  monto_estimado NUMERIC(14, 2) NOT NULL DEFAULT 0,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'pagado')),
  fecha_pago TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_obligaciones_pago_estado
  ON public.obligaciones_pago(estado);
CREATE INDEX IF NOT EXISTS idx_obligaciones_pago_vencimiento
  ON public.obligaciones_pago(fecha_vencimiento);

ALTER TABLE public.obligaciones_pago ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'obligaciones_pago_all_authenticated'
      AND tablename = 'obligaciones_pago'
  ) THEN
    CREATE POLICY "obligaciones_pago_all_authenticated" ON public.obligaciones_pago
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;


-- 2. CONFIGURACIÓN DE RENTABILIDAD FIJA
-- Espejo en SQLite: lib/core/database/local_database.dart (CREATE TABLE rentabilidad_config)
-- Pulled by: lib/core/services/sync_engine.dart -> _pullTable(db, 'rentabilidad_config', null)
CREATE TABLE IF NOT EXISTS public.rentabilidad_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alquiler_local NUMERIC(14, 2) NOT NULL DEFAULT 0,
  sueldos_admin NUMERIC(14, 2) NOT NULL DEFAULT 0,
  servicios_oficina NUMERIC(14, 2) NOT NULL DEFAULT 0,
  impuestos_fijos NUMERIC(14, 2) NOT NULL DEFAULT 0,
  honorario_adrian_default_monto NUMERIC(14, 2) NOT NULL DEFAULT 0,
  honorario_adrian_default_pct NUMERIC(10, 4) NOT NULL DEFAULT 0,
  honorario_modo_default TEXT NOT NULL DEFAULT 'monto' CHECK (honorario_modo_default IN ('monto', 'porcentaje')),
  eventos_estimados_mes INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ,
  updated_by TEXT
);

ALTER TABLE public.rentabilidad_config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'rentabilidad_config_all_authenticated'
      AND tablename = 'rentabilidad_config'
  ) THEN
    CREATE POLICY "rentabilidad_config_all_authenticated" ON public.rentabilidad_config
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;


-- 3. PRESUPUESTOS.fecha_evento
-- El SyncEngine (lib/core/services/sync_engine.dart, _cleanForSqlite) espera
-- esta columna para presupuestos. Si la cloud no la tiene, presupuestos creados
-- en otra PC pierden la fecha al sincronizar.
ALTER TABLE public.presupuestos
  ADD COLUMN IF NOT EXISTS fecha_evento TIMESTAMPTZ;
