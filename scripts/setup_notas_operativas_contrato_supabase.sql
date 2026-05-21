-- =========================================================================
-- NOTAS OPERATIVAS POR CONTRATO (eventos masivos)
-- Recordatorios internos por alumno/contrato; no afectan cuotas ni pagos.
--
-- Ejecutá este script completo en Supabase → SQL Editor → Run.
-- Espejo SQLite: tabla `notas_operativas_contrato` + SyncEngine pull/cola.
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.notas_operativas_contrato (
  id UUID PRIMARY KEY,
  contrato_alumno_id UUID NOT NULL REFERENCES public.contratos_alumnos(id) ON DELETE CASCADE,
  texto TEXT NOT NULL DEFAULT '',
  resuelto BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT notas_operativas_contrato_uniq_contrato UNIQUE (contrato_alumno_id)
);

CREATE INDEX IF NOT EXISTS idx_notas_operativas_contrato_alumno
  ON public.notas_operativas_contrato(contrato_alumno_id DESC);

CREATE INDEX IF NOT EXISTS idx_notas_operativas_contrato_updated
  ON public.notas_operativas_contrato(updated_at DESC);

COMMENT ON TABLE public.notas_operativas_contrato IS 'Notas operativas locales-equipo; sincronizadas; no contables';

ALTER TABLE public.notas_operativas_contrato ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'notas_operativas_contrato_all_authenticated'
      AND tablename = 'notas_operativas_contrato'
  ) THEN
    CREATE POLICY "notas_operativas_contrato_all_authenticated"
      ON public.notas_operativas_contrato
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;
