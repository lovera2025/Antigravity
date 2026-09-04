-- Cuentas pendientes con una persona: lo que el negocio le debe por un trabajo
-- que hizo o por un producto, y lo que se le fue pagando.
--
-- Espejo de la migración v70 de SQLite (local_database.dart) y del modelo
-- lib/features/mi_empresa/models/compromiso_personal.dart.
--
-- El saldo NO se guarda en ninguna columna: se deriva de los egresos que llevan
-- ese `compromiso_id`. Guardarlo sería una segunda fuente de verdad para la
-- misma plata y quedaría mintiendo apenas alguien editara o borrara un pago.
--
-- Correr entera en el SQL Editor ANTES de distribuir el build.

-- ROLLBACK: DROP TABLE IF EXISTS public.compromisos_personal;
CREATE TABLE IF NOT EXISTS public.compromisos_personal (
  id            UUID PRIMARY KEY,
  persona       TEXT NOT NULL,
  tipo          TEXT NOT NULL DEFAULT 'Trabajo',
  concepto      TEXT,
  monto_total   NUMERIC(14,2) NOT NULL DEFAULT 0,
  fecha_inicio  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  estado        TEXT NOT NULL DEFAULT 'activo',
  nota          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT compromisos_personal_estado_chk
    CHECK (estado IN ('activo', 'cancelado'))
);

-- Sin CHECK sobre `tipo`: la etiqueta de saldada se arma con ese texto, y un
-- tipo nuevo tiene que poder entrar sin migrar la base.

-- ROLLBACK: DROP INDEX IF EXISTS public.idx_compromisos_personal_persona;
CREATE INDEX IF NOT EXISTS idx_compromisos_personal_persona
  ON public.compromisos_personal(persona);

-- El pull incremental filtra por updated_at; sin este índice hace seq scan.
-- ROLLBACK: DROP INDEX IF EXISTS public.idx_compromisos_personal_updated;
CREATE INDEX IF NOT EXISTS idx_compromisos_personal_updated
  ON public.compromisos_personal(updated_at DESC);

-- Las dos columnas nuevas de egresos. Aditivas: nacen NULL en todo lo histórico
-- y NULL se comporta igual que antes, así que ningún saldo ya registrado se
-- mueve. `origen_fondos` separa el rubro (qué se pagó) de la bolsa (de dónde
-- salió), que hasta ahora convivían en `categoria`.
-- ROLLBACK: ALTER TABLE public.egresos DROP COLUMN IF EXISTS compromiso_id;
ALTER TABLE public.egresos
  ADD COLUMN IF NOT EXISTS compromiso_id UUID;

-- ROLLBACK: ALTER TABLE public.egresos DROP COLUMN IF EXISTS origen_fondos;
ALTER TABLE public.egresos
  ADD COLUMN IF NOT EXISTS origen_fondos TEXT;

-- ROLLBACK: DROP INDEX IF EXISTS public.idx_egresos_compromiso;
CREATE INDEX IF NOT EXISTS idx_egresos_compromiso
  ON public.egresos(compromiso_id);

ALTER TABLE public.compromisos_personal ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'compromisos_personal_all_authenticated'
      AND tablename = 'compromisos_personal'
  ) THEN
    CREATE POLICY "compromisos_personal_all_authenticated"
      ON public.compromisos_personal
      FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- Deliberadamente SIN `REPLICA IDENTITY FULL` y sin sumarla a la publicación
-- `supabase_realtime`: esa publicación quedó con una sola tabla (invitados, para
-- el tótem) porque Realtime se estaba comiendo el Disk IO del proyecto. Esta
-- tabla viaja por el pull incremental como el resto.
