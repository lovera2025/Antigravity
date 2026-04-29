-- Migración para añadir medio de pago a las tablas financieras
-- Esto permite separar ingresos/egresos en efectivo vs transferencias/tarjetas.

ALTER TABLE transacciones ADD COLUMN IF NOT EXISTS medio_pago TEXT;
ALTER TABLE pagos_contrato_alumno ADD COLUMN IF NOT EXISTS medio_pago TEXT;
ALTER TABLE pagos_prestamo_alquiler ADD COLUMN IF NOT EXISTS medio_pago TEXT;
ALTER TABLE egresos ADD COLUMN IF NOT EXISTS medio_pago TEXT;
