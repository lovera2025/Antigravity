-- ============================================================================
-- MIGRACIÓN IMPORTANTE: Persistencia de Pagos Extras
-- ============================================================================
-- Ejecutar en Supabase -> SQL Editor -> New query -> Run
-- ============================================================================

ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_pagado REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_pagado REAL DEFAULT 0.0;

-- Mensaje: Las columnas se crearon exitosamente.
