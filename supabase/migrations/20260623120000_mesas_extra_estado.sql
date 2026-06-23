-- Mesas extra múltiples: cantidad + estado JSON por mesa (additive, no destructivo)
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesa_extra_cantidad INTEGER DEFAULT 0;
ALTER TABLE contratos_alumnos ADD COLUMN IF NOT EXISTS mesas_extra_estado JSONB;
