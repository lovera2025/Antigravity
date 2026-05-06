-- Anulación no destructiva de cobros (Junior Eventos).
-- Ejecutar en Supabase SQL Editor si usás sincronización con la app de escritorio.
-- Los valores anulado usan 0 = vigente, 1 = anulado (alineado con SQLite local).

ALTER TABLE transacciones ADD COLUMN IF NOT EXISTS anulado integer NOT NULL DEFAULT 0;
ALTER TABLE transacciones ADD COLUMN IF NOT EXISTS motivo_anulacion text;
ALTER TABLE transacciones ADD COLUMN IF NOT EXISTS fecha_anulacion timestamptz;

ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS anulado integer NOT NULL DEFAULT 0;
ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS motivo_anulacion text;
ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS fecha_anulacion timestamptz;

ALTER TABLE pagos_prestamo_alquiler ADD COLUMN IF NOT EXISTS anulado integer NOT NULL DEFAULT 0;
ALTER TABLE pagos_prestamo_alquiler ADD COLUMN IF NOT EXISTS motivo_anulacion text;
ALTER TABLE pagos_prestamo_alquiler ADD COLUMN IF NOT EXISTS fecha_anulacion timestamptz;
