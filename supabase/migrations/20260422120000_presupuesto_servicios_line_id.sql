-- presupuesto_servicios: misma forma que SQLite / SyncEngine.
-- - PK por fila (id UUID), no (presupuesto_id, servicio_id) — permite repetir servicio en un presupuesto.
-- - cantidad, grupo, combo_orden para alinear con lib/core/database/local_database.dart
--
-- Ejecutar en Supabase → SQL (o supabase db push). Idempotente salvo nombre de tabla inexistente.

ALTER TABLE public.presupuesto_servicios
  ADD COLUMN IF NOT EXISTS cantidad NUMERIC DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS grupo TEXT,
  ADD COLUMN IF NOT EXISTS combo_orden INTEGER DEFAULT 0;

ALTER TABLE public.presupuesto_servicios ADD COLUMN IF NOT EXISTS id UUID;

UPDATE public.presupuesto_servicios SET id = gen_random_uuid() WHERE id IS NULL;

ALTER TABLE public.presupuesto_servicios ALTER COLUMN id SET NOT NULL;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.presupuesto_servicios'::regclass
      AND c.contype = 'p'
  LOOP
    EXECUTE format('ALTER TABLE public.presupuesto_servicios DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.presupuesto_servicios ADD PRIMARY KEY (id);

ALTER TABLE public.presupuesto_servicios
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

CREATE INDEX IF NOT EXISTS idx_presupuesto_servicios_presupuesto
  ON public.presupuesto_servicios (presupuesto_id);
