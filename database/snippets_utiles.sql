-- ============================================================================
-- SNIPPETS ÚTILES - Recepción Interactiva
-- Queries y comandos frecuentes para testing y administración
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════════
-- 📋 INFORMACIÓN Y DIAGNÓSTICO
-- ════════════════════════════════════════════════════════════════════════════

-- Obtener ID del primer evento disponible (copiar resultado para usar abajo)
SELECT id, tipo, fecha_evento FROM eventos LIMIT 5;

-- Ver todos los eventos activos con su información
SELECT 
  e.id,
  c.nombre_completo as cliente,
  e.tipo,
  e.fecha_evento,
  e.estado,
  COUNT(i.id) as total_invitados,
  COUNT(i.id) FILTER (WHERE i.estado_ingreso = 'ingresado') as ingresados
FROM eventos e
LEFT JOIN clientes c ON e.cliente_id = c.id
LEFT JOIN invitados i ON e.id = i.evento_id
WHERE e.estado NOT IN ('Finalizado', 'Cancelado')
GROUP BY e.id, c.nombre_completo, e.tipo, e.fecha_evento, e.estado
ORDER BY e.fecha_evento;

-- Verificar que la tabla invitados existe y tiene datos
SELECT 
  'Tabla existe' as status,
  COUNT(*) as total_registros
FROM invitados;

-- Ver estado de Realtime
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime';

-- Ver políticas RLS activas
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies 
WHERE tablename = 'invitados';

-- ════════════════════════════════════════════════════════════════════════════
-- 🧪 GENERACIÓN DE DATOS DE PRUEBA
-- ════════════════════════════════════════════════════════════════════════════

-- Generar 20 invitados para un evento específico
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT generar_invitados_prueba('<EVENTO_ID>', 20);

-- Generar 50 invitados para el primer evento disponible
SELECT generar_invitados_prueba((SELECT id FROM eventos LIMIT 1), 50);

-- Generar invitados con nombres específicos (inserción manual)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
INSERT INTO invitados (evento_id, nombre_completo, numero_mesa, estado_ingreso) VALUES
  ('<EVENTO_ID>', 'Juan Pérez', '1', 'pendiente'),
  ('<EVENTO_ID>', 'María González', '1', 'pendiente'),
  ('<EVENTO_ID>', 'Carlos Rodríguez', '2', 'pendiente'),
  ('<EVENTO_ID>', 'Ana Martínez', '2', 'pendiente'),
  ('<EVENTO_ID>', 'Luis Fernández', '3', 'pendiente');

-- ════════════════════════════════════════════════════════════════════════════
-- 📊 CONSULTAS Y ESTADÍSTICAS
-- ════════════════════════════════════════════════════════════════════════════

-- Ver estadísticas completas de un evento
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE estado_ingreso = 'ingresado') as ingresados,
  COUNT(*) FILTER (WHERE estado_ingreso = 'pendiente') as pendientes,
  ROUND(
    (COUNT(*) FILTER (WHERE estado_ingreso = 'ingresado')::numeric / 
     NULLIF(COUNT(*), 0) * 100), 
    2
  ) as porcentaje_completado
FROM invitados 
WHERE evento_id = '<EVENTO_ID>';

-- Ver lista completa de invitados de un evento
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  nombre_completo,
  numero_mesa,
  estado_ingreso,
  created_at,
  updated_at
FROM invitados 
WHERE evento_id = '<EVENTO_ID>'
ORDER BY nombre_completo;

-- Ver últimos 10 ingresos registrados
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  nombre_completo,
  numero_mesa,
  updated_at as hora_ingreso
FROM invitados 
WHERE evento_id = '<EVENTO_ID>' 
  AND estado_ingreso = 'ingresado'
ORDER BY updated_at DESC
LIMIT 10;

-- Ver invitados por mesa
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  numero_mesa,
  COUNT(*) as total_invitados,
  COUNT(*) FILTER (WHERE estado_ingreso = 'ingresado') as ingresados,
  COUNT(*) FILTER (WHERE estado_ingreso = 'pendiente') as pendientes
FROM invitados 
WHERE evento_id = '<EVENTO_ID>'
GROUP BY numero_mesa
ORDER BY numero_mesa::integer;

-- ════════════════════════════════════════════════════════════════════════════
-- 🔧 TESTING Y SIMULACIÓN
-- ════════════════════════════════════════════════════════════════════════════

-- Simular ingreso de UN invitado específico (para testing del tótem)
-- ⚠️ Reemplazar <INVITADO_ID> con un ID real
UPDATE invitados 
SET estado_ingreso = 'ingresado', updated_at = now()
WHERE id = '<INVITADO_ID>';

-- Simular ingreso de los primeros 5 invitados pendientes (testing de cola)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
UPDATE invitados 
SET estado_ingreso = 'ingresado', updated_at = now()
WHERE evento_id = '<EVENTO_ID>' 
  AND estado_ingreso = 'pendiente'
ORDER BY nombre_completo
LIMIT 5;

-- Simular ingreso MASIVO (testing de stress - cuidado!)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
UPDATE invitados 
SET estado_ingreso = 'ingresado', updated_at = now()
WHERE evento_id = '<EVENTO_ID>' 
  AND estado_ingreso = 'pendiente';

-- Resetear TODOS los estados a pendiente (útil para re-testing)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
UPDATE invitados 
SET estado_ingreso = 'pendiente', updated_at = null
WHERE evento_id = '<EVENTO_ID>';

-- Resetear solo un invitado específico
-- ⚠️ Reemplazar <INVITADO_ID> con un ID real
UPDATE invitados 
SET estado_ingreso = 'pendiente', updated_at = null
WHERE id = '<INVITADO_ID>';

-- ════════════════════════════════════════════════════════════════════════════
-- 🗑️ LIMPIEZA Y MANTENIMIENTO
-- ════════════════════════════════════════════════════════════════════════════

-- Eliminar TODOS los invitados de un evento (cuidado!)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
DELETE FROM invitados WHERE evento_id = '<EVENTO_ID>';

-- Eliminar solo invitados pendientes de un evento
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
DELETE FROM invitados 
WHERE evento_id = '<EVENTO_ID>' 
  AND estado_ingreso = 'pendiente';

-- Eliminar invitados sin mesa asignada
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
DELETE FROM invitados 
WHERE evento_id = '<EVENTO_ID>' 
  AND numero_mesa IS NULL;

-- Vaciar completamente la tabla (⚠️ PELIGROSO - solo para testing)
TRUNCATE TABLE invitados CASCADE;

-- ════════════════════════════════════════════════════════════════════════════
-- ✏️ EDICIÓN MANUAL
-- ════════════════════════════════════════════════════════════════════════════

-- Cambiar nombre de un invitado
-- ⚠️ Reemplazar <INVITADO_ID> y 'NUEVO NOMBRE' con valores reales
UPDATE invitados 
SET nombre_completo = 'NUEVO NOMBRE'
WHERE id = '<INVITADO_ID>';

-- Cambiar número de mesa
-- ⚠️ Reemplazar <INVITADO_ID> y 'NUEVO_NUMERO' con valores reales
UPDATE invitados 
SET numero_mesa = 'NUEVO_NUMERO'
WHERE id = '<INVITADO_ID>';

-- Asignar mesas automáticamente en bloques de 8 personas
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY nombre_completo) as row_num
  FROM invitados
  WHERE evento_id = '<EVENTO_ID>'
)
UPDATE invitados i
SET numero_mesa = (CEIL(n.row_num::numeric / 8))::text
FROM numbered n
WHERE i.id = n.id;

-- ════════════════════════════════════════════════════════════════════════════
-- 🔍 BÚSQUEDAS AVANZADAS
-- ════════════════════════════════════════════════════════════════════════════

-- Buscar invitados por nombre (similar al buscador de la app)
-- ⚠️ Reemplazar <EVENTO_ID> y 'TEXTO' con valores reales
SELECT nombre_completo, numero_mesa, estado_ingreso
FROM invitados
WHERE evento_id = '<EVENTO_ID>'
  AND nombre_completo ILIKE '%TEXTO%'
ORDER BY nombre_completo;

-- Buscar invitados duplicados (mismo nombre)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT nombre_completo, COUNT(*) as cantidad
FROM invitados
WHERE evento_id = '<EVENTO_ID>'
GROUP BY nombre_completo
HAVING COUNT(*) > 1;

-- Ver invitados sin mesa asignada
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT nombre_completo, estado_ingreso
FROM invitados
WHERE evento_id = '<EVENTO_ID>'
  AND numero_mesa IS NULL;

-- ════════════════════════════════════════════════════════════════════════════
-- 📈 REPORTES
-- ════════════════════════════════════════════════════════════════════════════

-- Reporte de asistencia por hora (últimas 24 horas)
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  DATE_TRUNC('hour', updated_at) as hora,
  COUNT(*) as ingresos
FROM invitados
WHERE evento_id = '<EVENTO_ID>'
  AND estado_ingreso = 'ingresado'
  AND updated_at >= NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', updated_at)
ORDER BY hora;

-- Reporte completo de un evento para exportar
-- ⚠️ Reemplazar <EVENTO_ID> con un ID real
SELECT 
  e.tipo as tipo_evento,
  c.nombre_completo as cliente,
  e.fecha_evento,
  i.nombre_completo as invitado,
  i.numero_mesa,
  i.estado_ingreso,
  i.created_at as fecha_registro,
  i.updated_at as fecha_ingreso
FROM invitados i
JOIN eventos e ON i.evento_id = e.id
JOIN clientes c ON e.cliente_id = c.id
WHERE i.evento_id = '<EVENTO_ID>'
ORDER BY i.estado_ingreso DESC, i.nombre_completo;

-- ════════════════════════════════════════════════════════════════════════════
-- 🔧 MANTENIMIENTO DE LA TABLA
-- ════════════════════════════════════════════════════════════════════════════

-- Ver tamaño de la tabla
SELECT pg_size_pretty(pg_total_relation_size('invitados')) as tamaño_total;

-- Ver número total de registros históricos
SELECT COUNT(*) as total_historico FROM invitados;

-- Vacuum y analyze (optimización)
VACUUM ANALYZE invitados;

-- ════════════════════════════════════════════════════════════════════════════
-- 💡 TIPS Y MEJORES PRÁCTICAS
-- ════════════════════════════════════════════════════════════════════════════

/*
1. TESTING RÁPIDO:
   - Usa generar_invitados_prueba() para crear datos rápido
   - Usa UPDATE con LIMIT 5 para simular ingresos graduales
   - Usa RESETEAR desde la app para no escribir SQL

2. PRODUCCIÓN:
   - NUNCA uses TRUNCATE en producción
   - SIEMPRE verifica el <EVENTO_ID> antes de ejecutar UPDATE/DELETE
   - Haz backups antes de limpiezas masivas

3. PERFORMANCE:
   - Los índices ya están creados en el script principal
   - Si tienes +1000 invitados, considera paginación en la app
   - VACUUM regularmente para mantener performance

4. DEBUGGING:
   - Usa las queries de "INFORMACIÓN Y DIAGNÓSTICO" primero
   - Verifica Realtime en Supabase Dashboard
   - Consulta logs: Dashboard → Logs

5. SEGURIDAD:
   - Las políticas RLS están activas por defecto
   - Solo usuarios autenticados pueden acceder
   - Revisa periódicamente las políticas
*/

-- ============================================================================
-- FIN DE SNIPPETS
-- ============================================================================
