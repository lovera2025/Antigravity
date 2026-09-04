-- Vínculo declarado entre un evento particular y el presupuesto que lo creó.
--
-- Espejo de la migración v69 de SQLite (local_database.dart) y del campo
-- `Evento.presupuestoId` (lib/models/evento.dart).
--
-- Por qué hace falta. Al confirmar un presupuesto, `confirmarPresupuesto` copia
-- sus ítems al evento reusando el id de cada línea, así que hasta ahora el
-- origen se podía rastrear cruzando `eventos_servicios.id = presupuesto_servicios.id`.
-- Ese rastro vive en las filas copiadas: un evento que se creó SIN ítems no tiene
-- ninguna, y es justo el que hay que reparar. Declarar el vínculo en el evento lo
-- hace sobrevivir aunque el evento esté vacío.
--
-- Correr entera en el SQL Editor ANTES de distribuir el build.

-- ROLLBACK: ALTER TABLE public.eventos DROP COLUMN IF EXISTS presupuesto_id;
ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS presupuesto_id UUID;

-- Sin REFERENCES a propósito: `eventos` es vieja —su `evento_id` en egresos ya
-- tuvo que volverse nullable a la fuerza— y una FK nueva solo agrega formas de
-- que falle un insert. La integridad se cuida en el repositorio.

-- ROLLBACK: DROP INDEX IF EXISTS public.idx_eventos_presupuesto;
CREATE INDEX IF NOT EXISTS idx_eventos_presupuesto
  ON public.eventos(presupuesto_id);

-- Relleno hacia atrás, paso 1: los eventos que convirtieron bien se rastrean por
-- el id compartido de las líneas. Determinístico, no adivina nada.
-- ROLLBACK: UPDATE public.eventos SET presupuesto_id = NULL;
UPDATE public.eventos e
SET presupuesto_id = sub.presupuesto_id
FROM (
  SELECT DISTINCT ON (es.evento_id) es.evento_id, ps.presupuesto_id
  FROM public.eventos_servicios es
  JOIN public.presupuesto_servicios ps ON ps.id = es.id
) AS sub
WHERE e.id = sub.evento_id
  AND e.presupuesto_id IS NULL;

-- Relleno hacia atrás, paso 2: los eventos que se crearon VACÍOS no tienen filas
-- de las que colgarse. Para esos se cruza por cliente y fecha, y solo cuando hay
-- un único presupuesto candidato: con dos, adivinar sería peor que no vincular.
-- ROLLBACK: UPDATE public.eventos SET presupuesto_id = NULL;
UPDATE public.eventos e
SET presupuesto_id = sub.presupuesto_id
FROM (
  -- `array_agg(...)[1]` y no `MIN(p.id)`: Postgres no tiene MIN para uuid.
  -- El HAVING de abajo garantiza que haya exactamente uno, así que tomar el
  -- primero es tomar el único.
  SELECT ev.id AS evento_id, (array_agg(p.id))[1] AS presupuesto_id
  FROM public.eventos ev
  JOIN public.presupuestos p
    ON p.cliente_id = ev.cliente_id
   AND p.fecha_evento::date = ev.fecha_evento::date
  WHERE ev.presupuesto_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.eventos_servicios es WHERE es.evento_id = ev.id
    )
  GROUP BY ev.id
  HAVING COUNT(p.id) = 1
) AS sub
WHERE e.id = sub.evento_id
  AND e.presupuesto_id IS NULL;

-- Control: cuántos quedaron vinculados y cuáles siguen sin ítems.
SELECT
  (SELECT COUNT(*) FROM public.eventos WHERE presupuesto_id IS NOT NULL)
    AS eventos_vinculados,
  (SELECT COUNT(*) FROM public.eventos ev
    WHERE ev.modalidad = 'particular'
      AND NOT EXISTS (
        SELECT 1 FROM public.eventos_servicios es WHERE es.evento_id = ev.id))
    AS particulares_sin_items;
