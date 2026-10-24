-- ============================================================================
-- MIGRACIÓN CORREGIDA - Sistema de Validación DNI
-- ============================================================================
-- Ejecutar TODO este script de una vez en Supabase SQL Editor
-- ============================================================================

-- PASO 1: Agregar columnas a invitados
-- ============================================================================
ALTER TABLE invitados 
ADD COLUMN IF NOT EXISTS dni TEXT,
ADD COLUMN IF NOT EXISTS intentos_fallidos INTEGER DEFAULT 0;

-- PASO 2: Crear índice en DNI
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_invitados_dni ON invitados(dni);

-- PASO 3: Crear tabla de accesos (auditoría)
-- ============================================================================
CREATE TABLE IF NOT EXISTS accesos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invitado_id UUID NOT NULL REFERENCES invitados(id) ON DELETE CASCADE,
    evento_id UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    dni_ingresado TEXT NOT NULL,
    valido BOOLEAN NOT NULL DEFAULT false,
    marcado_por TEXT,
    ip_dispositivo TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- PASO 4: Crear índices para tabla accesos
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_accesos_invitado ON accesos(invitado_id);
CREATE INDEX IF NOT EXISTS idx_accesos_evento ON accesos(evento_id);
CREATE INDEX IF NOT EXISTS idx_accesos_timestamp ON accesos(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_accesos_valido ON accesos(valido);

-- PASO 5: Habilitar Row Level Security (RLS)
-- ============================================================================
ALTER TABLE accesos ENABLE ROW LEVEL SECURITY;

-- PASO 6: Eliminar políticas existentes (si existen)
-- ============================================================================
DROP POLICY IF EXISTS "Permitir inserción de accesos" ON accesos;
DROP POLICY IF EXISTS "Permitir lectura de accesos" ON accesos;

-- PASO 7: Crear políticas de seguridad
-- ============================================================================
-- Permitir inserción desde cualquier usuario (para totem público)
CREATE POLICY "Permitir inserción de accesos" ON accesos
    FOR INSERT
    WITH CHECK (true);

-- Permitir lectura solo a usuarios autenticados
CREATE POLICY "Permitir lectura de accesos" ON accesos
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- PASO 8: Agregar DNIs de prueba a invitados existentes
-- ============================================================================
-- SOLO PARA DESARROLLO - En producción, agregar DNIs reales
UPDATE invitados 
SET dni = LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0')
WHERE dni IS NULL OR dni = '';

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

-- 1. Verificar que todos los invitados tienen DNI
SELECT 
    COUNT(*) as total_invitados,
    COUNT(CASE WHEN dni IS NOT NULL AND dni != '' THEN 1 END) as con_dni,
    COUNT(CASE WHEN dni IS NULL OR dni = '' THEN 1 END) as sin_dni
FROM invitados;

-- 2. Ver algunos invitados con DNI
SELECT id, nombre_completo, dni, intentos_fallidos, numero_mesa
FROM invitados 
LIMIT 5;

-- 3. Ver estructura de tabla accesos
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'accesos'
ORDER BY ordinal_position;

-- ============================================================================
-- ✅ MIGRACIÓN COMPLETADA
-- ============================================================================
-- Si ves los resultados de verificación sin errores, ¡todo está listo!
-- 
-- Próximo paso: Ejecutar la app con `flutter run -d windows`
-- ============================================================================
