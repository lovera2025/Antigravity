-- Homenajeado / motivo del festejo (eventos particulares).
-- Requerido por app SQLite v59 + sync_engine (titulo_festejado en eventos).
ALTER TABLE public.eventos ADD COLUMN IF NOT EXISTS titulo_festejado TEXT;

COMMENT ON COLUMN public.eventos.titulo_festejado IS
  'Motivo del festejo o nombre del homenajeado (ej. Los 15 de Pauli). Cliente = solicitante.';
