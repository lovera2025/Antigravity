-- ============================================================================
-- SOLUCION DEFINITIVA: Persistencia de Pagos Extras (Mesas y Sillas)
-- ============================================================================
-- Instrucciones PUNTUALES:
-- 1. Ve a https://supabase.com y entra a tu proyecto JuniorEventos.
-- 2. En el menú lateral izquierdo, haz clic en "SQL Editor" (el ícono de código).
-- 3. Crea una "New query" (Nueva consulta).
-- 4. Copia TODO el contenido de este archivo y pégalo allí.
-- 5. Haz clic en el botón verde "Run" que está abajo a la derecha.
-- 6. Debe decir "Success" o "No rows returned".
-- ============================================================================

ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_pagado REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS sillas_extra_pagado REAL DEFAULT 0.0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS porcentaje_descuento REAL DEFAULT 0.0;
