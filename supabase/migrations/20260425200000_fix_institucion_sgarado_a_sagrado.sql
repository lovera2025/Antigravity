-- Corrige typo de institución: SGARADO/sagrado -> SAGRADO
-- No borra filas; solo actualiza el texto. Idempotente (re-ejecutar no duplica cambios).
-- Opcional: ejecutar en Supabase SQL Editor si querés que quede persistido en la nube igual que en la app.

UPDATE public.contratos_alumnos
SET institucion = 'SAGRADO'
WHERE TRIM(LOWER(institucion)) IN ('sgarado', 'sagrado');
