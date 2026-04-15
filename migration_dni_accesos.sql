-- ============================================================================
-- MIGRACIÓN: Agregar DNI y sistema de accesos
-- ============================================================================

-- 1. Agregar columnas DNI e intentos_fallidos a la tabla invitados
ALTER TABLE invitados 
ADD COLUMN IF NOT EXISTS dni TEXT,
ADD COLUMN IF NOT EXISTS intentos_fallidos INTEGER DEFAULT 0;

-- 2. Hacer DNI obligatorio (después de agregar datos de prueba)
-- IMPORTANTE: Primero ejecutar UPDATE con DNIs de prueba antes de esta línea
-- ALTER TABLE invitados ALTER COLUMN dni SET NOT NULL;

-- 3. Crear índice en DNI para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_invitados_dni ON invitados(dni);

-- 4. Crear tabla de accesos (auditoría)
CREATE TABLE IF NOT EXISTS accesos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invitado_id UUID NOT NULL REFERENCES invitados(id) ON DELETE CASCADE,
    evento_id UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    dni_ingresado TEXT NOT NULL,
    valido BOOLEAN NOT NULL DEFAULT false,
    marcado_por TEXT,
    ip_dispositivo TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT fk_invitado FOREIGN KEY (invitado_id) REFERENCES invitados(id),
    CONSTRAINT fk_evento FOREIGN KEY (evento_id) REFERENCES eventos(id)
);

-- 5. Crear índices para la tabla accesos
CREATE INDEX IF NOT EXISTS idx_accesos_invitado ON accesos(invitado_id);
CREATE INDEX IF NOT EXISTS idx_accesos_evento ON accesos(evento_id);
CREATE INDEX IF NOT EXISTS idx_accesos_timestamp ON accesos(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_accesos_valido ON accesos(valido);

-- 6. Habilitar Row Level Security (RLS) en accesos
ALTER TABLE accesos ENABLE ROW LEVEL SECURITY;

-- 7. Políticas de seguridad para accesos (ajustar según tus necesidades)
-- Permitir inserción desde cualquier usuario autenticado
CREATE POLICY "Permitir inserción de accesos" ON accesos
    FOR INSERT
    WITH CHECK (true);

-- Permitir lectura solo a usuarios autenticados
CREATE POLICY "Permitir lectura de accesos" ON accesos
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- 8. Actualizar políticas de invitados si es necesario
-- (Asegurarse de que el campo DNI esté protegido)

-- ============================================================================
-- DATOS DE PRUEBA (OPCIONAL - Comentar en producción)
-- ============================================================================

-- Actualizar invitados existentes con DNIs de prueba
-- IMPORTANTE: Reemplazar con DNIs reales antes de producción
UPDATE invitados 
SET dni = LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0')
WHERE dni IS NULL;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- Verificar que todos los invitados tienen DNI
SELECT COUNT(*) as invitados_sin_dni 
FROM invitados 
WHERE dni IS NULL OR dni = '';

-- Ver estructura de la tabla accesos
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'accesos';

-- ============================================================================
-- ROLLBACK (En caso de necesitar revertir)
-- ============================================================================

-- Para revertir los cambios, ejecutar:
-- DROP TABLE IF EXISTS accesos CASCADE;
-- ALTER TABLE invitados DROP COLUMN IF EXISTS dni;
-- ALTER TABLE invitados DROP COLUMN IF EXISTS intentos_fallidos;
