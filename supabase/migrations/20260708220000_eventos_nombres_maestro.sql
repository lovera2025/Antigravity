-- Nombres estructurados para eventos particulares (Maestro Pro v60).
ALTER TABLE public.eventos ADD COLUMN IF NOT EXISTS nombre_festejado TEXT;
ALTER TABLE public.eventos ADD COLUMN IF NOT EXISTS encabezado_evento TEXT;

ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS nombre_festejado TEXT;
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS encabezado_evento TEXT;

COMMENT ON COLUMN public.eventos.nombre_festejado IS
  'Nombre corto del festejado/a (ej. Pauli). La redacción comercial la genera la IA.';
COMMENT ON COLUMN public.eventos.encabezado_evento IS
  'Título grande opcional para PDF/UI (ej. LOS 15 DE PAULI).';
