-- ============================================================================
-- ARGÜELLO EVENTS - Módulo de Recepción Interactiva
-- Script de configuración para tabla de invitados y realtime
-- ============================================================================

-- ── 1. CREAR TABLA INVITADOS ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS invitados (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  evento_id uuid NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
  nombre_completo text NOT NULL,
  numero_mesa text,
  estado_ingreso text NOT NULL DEFAULT 'pendiente' CHECK (estado_ingreso IN ('pendiente', 'ingresado')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- ── 2. ÍNDICES PARA PERFORMANCE ───────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_invitados_evento_id ON invitados(evento_id);
CREATE INDEX IF NOT EXISTS idx_invitados_estado ON invitados(estado_ingreso);
CREATE INDEX IF NOT EXISTS idx_invitados_nombre ON invitados USING gin (to_tsvector('spanish', nombre_completo));

-- ── 3. TRIGGER PARA AUTO-UPDATE TIMESTAMP ─────────────────────────────────

CREATE OR REPLACE FUNCTION update_invitados_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_invitados_timestamp ON invitados;
CREATE TRIGGER trigger_update_invitados_timestamp
  BEFORE UPDATE ON invitados
  FOR EACH ROW
  EXECUTE FUNCTION update_invitados_updated_at();

-- ── 4. ROW LEVEL SECURITY (RLS) ───────────────────────────────────────────

-- Habilitar RLS
ALTER TABLE invitados ENABLE ROW LEVEL SECURITY;

-- Política: Permitir SELECT para usuarios autenticados
CREATE POLICY "Usuarios autenticados pueden ver invitados"
  ON invitados FOR SELECT
  TO authenticated
  USING (true);

-- Política: Permitir INSERT para usuarios autenticados
CREATE POLICY "Usuarios autenticados pueden crear invitados"
  ON invitados FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Política: Permitir UPDATE para usuarios autenticados
CREATE POLICY "Usuarios autenticados pueden actualizar invitados"
  ON invitados FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Política: Permitir DELETE para usuarios autenticados
CREATE POLICY "Usuarios autenticados pueden eliminar invitados"
  ON invitados FOR DELETE
  TO authenticated
  USING (true);

-- ── 5. HABILITAR REALTIME EN SUPABASE ────────────────────────────────────
-- IMPORTANTE: Ejecutar esto en el Dashboard de Supabase o via SQL Editor:
-- 1. Ve a Database → Replication
-- 2. Activa la tabla 'invitados' para realtime
-- 3. O ejecuta el siguiente comando si tienes permisos:

-- ALTER PUBLICATION supabase_realtime ADD TABLE invitados;

-- ── 6. DATOS DE PRUEBA ────────────────────────────────────────────────────
-- NOTA: Reemplaza '<EVENTO_ID>' con un ID real de tu tabla 'eventos'
-- Puedes obtener un ID ejecutando: SELECT id FROM eventos LIMIT 1;

-- Ejemplo de inserción (comentado por defecto):
/*
INSERT INTO invitados (evento_id, nombre_completo, numero_mesa, estado_ingreso) VALUES
  ('<EVENTO_ID>', 'Juan Pérez Gómez', '1', 'pendiente'),
  ('<EVENTO_ID>', 'María Rodríguez López', '1', 'pendiente'),
  ('<EVENTO_ID>', 'Carlos Fernández Martínez', '2', 'pendiente'),
  ('<EVENTO_ID>', 'Ana García Torres', '2', 'pendiente'),
  ('<EVENTO_ID>', 'Luis Martínez Sánchez', '3', 'pendiente'),
  ('<EVENTO_ID>', 'Laura González Ruiz', '3', 'pendiente'),
  ('<EVENTO_ID>', 'Pedro López Díaz', '4', 'pendiente'),
  ('<EVENTO_ID>', 'Carmen Sánchez Moreno', '4', 'pendiente'),
  ('<EVENTO_ID>', 'Jorge Ramírez Castro', '5', 'pendiente'),
  ('<EVENTO_ID>', 'Sofía Torres Vargas', '5', 'pendiente'),
  ('<EVENTO_ID>', 'Miguel Ángel Flores', '6', 'pendiente'),
  ('<EVENTO_ID>', 'Isabel Romero Jiménez', '6', 'pendiente'),
  ('<EVENTO_ID>', 'Fernando Castillo Ortiz', '7', 'pendiente'),
  ('<EVENTO_ID>', 'Patricia Morales Herrera', '7', 'pendiente'),
  ('<EVENTO_ID>', 'Roberto Gutiérrez Luna', '8', 'pendiente'),
  ('<EVENTO_ID>', 'Gabriela Mendoza Silva', '8', 'pendiente'),
  ('<EVENTO_ID>', 'Andrés Vega Paredes', '9', 'pendiente'),
  ('<EVENTO_ID>', 'Valentina Cruz Reyes', '9', 'pendiente'),
  ('<EVENTO_ID>', 'Diego Navarro Campos', '10', 'pendiente'),
  ('<EVENTO_ID>', 'Camila Herrera Rojas', '10', 'pendiente');
*/

-- ── 7. FUNCIÓN HELPER PARA GENERAR INVITADOS DE PRUEBA ───────────────────

CREATE OR REPLACE FUNCTION generar_invitados_prueba(
  p_evento_id uuid,
  p_cantidad integer DEFAULT 20
)
RETURNS void AS $$
DECLARE
  v_nombres text[] := ARRAY[
    'Juan', 'María', 'Carlos', 'Ana', 'Luis', 'Laura', 'Pedro', 'Carmen',
    'Jorge', 'Sofía', 'Miguel', 'Isabel', 'Fernando', 'Patricia', 'Roberto',
    'Gabriela', 'Andrés', 'Valentina', 'Diego', 'Camila', 'Javier', 'Lucía',
    'Ricardo', 'Daniela', 'Sebastián', 'Natalia', 'Martín', 'Victoria'
  ];
  v_apellidos text[] := ARRAY[
    'Pérez', 'Rodríguez', 'Fernández', 'García', 'Martínez', 'González',
    'López', 'Sánchez', 'Ramírez', 'Torres', 'Flores', 'Romero', 'Castillo',
    'Morales', 'Gutiérrez', 'Mendoza', 'Vega', 'Cruz', 'Navarro', 'Herrera'
  ];
  v_nombre_completo text;
  v_numero_mesa integer;
BEGIN
  FOR i IN 1..p_cantidad LOOP
    v_nombre_completo := v_nombres[1 + floor(random() * array_length(v_nombres, 1))] || ' ' ||
                         v_apellidos[1 + floor(random() * array_length(v_apellidos, 1))] || ' ' ||
                         v_apellidos[1 + floor(random() * array_length(v_apellidos, 1))];
    v_numero_mesa := 1 + floor(random() * 15);
    
    INSERT INTO invitados (evento_id, nombre_completo, numero_mesa, estado_ingreso)
    VALUES (p_evento_id, v_nombre_completo, v_numero_mesa::text, 'pendiente');
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ── 8. EJEMPLO DE USO DE LA FUNCIÓN HELPER ───────────────────────────────
/*
-- Generar 30 invitados para un evento específico:
SELECT generar_invitados_prueba('<EVENTO_ID>', 30);

-- O para el primer evento disponible:
SELECT generar_invitados_prueba((SELECT id FROM eventos LIMIT 1), 30);
*/

-- ── 9. CONSULTAS ÚTILES PARA TESTING ─────────────────────────────────────

-- Ver todos los invitados de un evento:
-- SELECT * FROM invitados WHERE evento_id = '<EVENTO_ID>' ORDER BY nombre_completo;

-- Ver estadísticas de un evento:
-- SELECT 
--   COUNT(*) as total,
--   COUNT(*) FILTER (WHERE estado_ingreso = 'ingresado') as ingresados,
--   COUNT(*) FILTER (WHERE estado_ingreso = 'pendiente') as pendientes
-- FROM invitados 
-- WHERE evento_id = '<EVENTO_ID>';

-- Simular ingreso de un invitado (para testing del tótem):
-- UPDATE invitados 
-- SET estado_ingreso = 'ingresado', updated_at = now()
-- WHERE id = '<INVITADO_ID>';

-- Resetear todos los estados a 'pendiente' (útil para testing):
-- UPDATE invitados 
-- SET estado_ingreso = 'pendiente', updated_at = now()
-- WHERE evento_id = '<EVENTO_ID>';

-- ── 10. VERIFICACIÓN DE CONFIGURACIÓN ────────────────────────────────────

-- Verificar que la tabla existe:
-- SELECT EXISTS (
--   SELECT FROM pg_tables 
--   WHERE schemaname = 'public' 
--   AND tablename = 'invitados'
-- );

-- Verificar políticas RLS:
-- SELECT * FROM pg_policies WHERE tablename = 'invitados';

-- Verificar triggers:
-- SELECT * FROM pg_trigger WHERE tgname LIKE '%invitados%';

-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================

-- PASOS SIGUIENTES:
-- 1. Ejecutar este script en el SQL Editor de Supabase
-- 2. Ir a Database → Replication → habilitar 'invitados' para Realtime
-- 3. Ejecutar generar_invitados_prueba() para crear datos de prueba
-- 4. Probar la conexión desde la app Flutter
