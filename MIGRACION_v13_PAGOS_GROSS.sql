-- ============================================================================
-- MIGRACIÓN INTEGRAL v3 al v13: Sincronización de Esquema Masivo
-- ============================================================================
-- Ejecutar en Supabase -> SQL Editor -> New query -> Run
-- ============================================================================

-- 1. Asegurar columnas en contratos_alumnos (v3 al v12)
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_precio REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_cuotas INTEGER DEFAULT 1;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_cuotas_pagadas INTEGER DEFAULT 0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_pagado REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_cantidad INTEGER DEFAULT 0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_cuotas INTEGER DEFAULT 1;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_precio_total REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_cuotas_pagadas INTEGER DEFAULT 0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_pagado REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS curso_division TEXT;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS musica_elegida TEXT;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS numero_mesa TEXT;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS telefono TEXT;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS porcentaje_descuento REAL DEFAULT 0.0;

-- 2. Asegurar columnas en pagos_contrato_alumno (v13: Pagos Gross)
ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS monto_gross REAL;
ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS descuento_porcentaje REAL DEFAULT 0.0;

-- Sincronizar monto_gross con el monto actual para registros existentes (migración v13)
UPDATE pagos_contrato_alumno SET monto_gross = monto WHERE monto_gross IS NULL;
