-- ============================================================================
-- MIGRACIÓN SUPABASE: Agregar Columna "observaciones"
-- ============================================================================
-- Instrucciones:
-- 1. Ve a tu panel de Supabase -> SQL Editor.
-- 2. Abre una "New query".
-- 3. Pega este código y presiona "Run".
-- ============================================================================

ALTER TABLE eventos ADD COLUMN IF NOT EXISTS observaciones TEXT;

-- Mensaje: Columna añadida exitosamente.
