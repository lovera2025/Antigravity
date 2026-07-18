-- Tablas espejo para sesiones de caja (MVP).
-- Ejecutar en Supabase SQL editor si aún no existen.

CREATE TABLE IF NOT EXISTS operadores_caja (
  id TEXT PRIMARY KEY,
  nombre TEXT NOT NULL,
  pin TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS sesiones_caja (
  id TEXT PRIMARY KEY,
  operador_id TEXT NOT NULL REFERENCES operadores_caja(id),
  abierta_at TIMESTAMPTZ NOT NULL,
  cerrada_at TIMESTAMPTZ,
  cambio_inicial DOUBLE PRECISION NOT NULL DEFAULT 0,
  nota_apertura TEXT,
  etiqueta TEXT,
  arqueo_cierre DOUBLE PRECISION,
  nota_cierre TEXT,
  device_id TEXT,
  last_heartbeat TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sesiones_caja_abierta
  ON sesiones_caja (cerrada_at, abierta_at);

-- Conserva solo la apertura más reciente si una prueba dejó duplicadas.
WITH abiertas AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY operador_id
           ORDER BY abierta_at DESC, id DESC
         ) AS rn
  FROM sesiones_caja
  WHERE cerrada_at IS NULL
)
UPDATE sesiones_caja s
SET cerrada_at = NOW(),
    updated_at = NOW(),
    nota_cierre = COALESCE(
      nota_cierre,
      'Cerrada al normalizar sesiones duplicadas'
    )
FROM abiertas a
WHERE s.id = a.id AND a.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sesiones_caja_operador_unica_abierta
  ON sesiones_caja (operador_id)
  WHERE cerrada_at IS NULL;

ALTER TABLE pagos_contrato_alumno
  ADD COLUMN IF NOT EXISTS sesion_caja_id TEXT;

-- Aditivo y compatible con builds anteriores: no se aplica todavía CHECK
-- sobre etiqueta para que clientes viejos puedan seguir sincronizando.
ALTER TABLE egresos
  ADD COLUMN IF NOT EXISTS sesion_caja_id TEXT;

ALTER TABLE cierre_caja_guia_movimientos
  ADD COLUMN IF NOT EXISTS sesion_caja_id TEXT;

ALTER TABLE cierre_caja_anotaciones
  ADD COLUMN IF NOT EXISTS sesion_caja_id TEXT;

ALTER TABLE cierre_caja_anotaciones
  DROP CONSTRAINT IF EXISTS cierre_caja_anotaciones_fecha_turno_key;

CREATE INDEX IF NOT EXISTS idx_egresos_sesion_caja
  ON egresos (sesion_caja_id);

CREATE INDEX IF NOT EXISTS idx_guia_cambio_sesion
  ON cierre_caja_guia_movimientos (sesion_caja_id, fecha_mov);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cierre_anotacion_sesion
  ON cierre_caja_anotaciones (sesion_caja_id)
  WHERE sesion_caja_id IS NOT NULL;
