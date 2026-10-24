-- =========================================================================
-- JUNIOR EVENTOS - ACTUALIZACIÓN DE ESQUEMA V20 (SUPABASE)
-- Corrección: PGRST204 (Could not find the 'grupo' column)
-- =========================================================================

-- 1. Añadimos la columna 'grupo' que permite agrupar servicios en el presupuesto
ALTER TABLE public.presupuesto_servicios ADD COLUMN IF NOT EXISTS grupo TEXT;
ALTER TABLE public.eventos_servicios ADD COLUMN IF NOT EXISTS grupo TEXT;

-- 2. Aseguramos la existencia de 'cantidad' que venía de una migración anterior
ALTER TABLE public.presupuesto_servicios ADD COLUMN IF NOT EXISTS cantidad NUMERIC DEFAULT 1.0;
ALTER TABLE public.eventos_servicios ADD COLUMN IF NOT EXISTS cantidad NUMERIC DEFAULT 1.0;

-- 3. Mensaje de éxito
-- En Supabase la ejecución sin errores confirmará la aplicación.
