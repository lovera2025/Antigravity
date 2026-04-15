-- ============================================================================
-- FIX: Habilitar RLS en TODAS las tablas del schema public
-- Fecha: 25 Marzo 2026
-- Motivo: Alerta de Supabase "rls_disabled_in_public"
-- ============================================================================
-- 
-- INSTRUCCIONES: 
--   1. Ir al Dashboard de Supabase → SQL Editor
--   2. Pegar este script completo
--   3. Ejecutar
--
-- NOTA: Este script usa IF NOT EXISTS / DROP IF EXISTS para ser idempotente
--       (se puede ejecutar múltiples veces sin problemas)
-- ============================================================================

-- ── PASO 1: Verificar qué tablas NO tienen RLS habilitado ──────────────────
-- (Ejecutar primero para ver el estado actual)

SELECT 
  schemaname, 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- ── PASO 2: Habilitar RLS en tablas que podrían faltar ─────────────────────

-- Tablas del schema principal (schema.sql)
ALTER TABLE IF EXISTS public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.eventos_servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.transacciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.egresos ENABLE ROW LEVEL SECURITY;

-- Tablas de migraciones posteriores (contratos y pagos - MUY PROBABLE QUE FALTEN)
ALTER TABLE IF EXISTS public.contratos_alumnos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.pagos_contrato_alumno ENABLE ROW LEVEL SECURITY;

-- Tabla de invitados (módulo recepción)
ALTER TABLE IF EXISTS public.invitados ENABLE ROW LEVEL SECURITY;

-- Tabla de accesos (módulo DNI)
ALTER TABLE IF EXISTS public.accesos ENABLE ROW LEVEL SECURITY;

-- Tabla de solicitudes (catálogo QR público)
ALTER TABLE IF EXISTS public.solicitudes_cotizacion ENABLE ROW LEVEL SECURITY;

-- ── PASO 3: Crear políticas para tablas que NO las tienen ──────────────────

-- === contratos_alumnos ===
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'contratos_alumnos' AND policyname = 'Full access contratos_alumnos'
  ) THEN
    CREATE POLICY "Full access contratos_alumnos" 
    ON public.contratos_alumnos FOR ALL 
    TO authenticated 
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;

-- === pagos_contrato_alumno ===
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'pagos_contrato_alumno' AND policyname = 'Full access pagos_contrato_alumno'
  ) THEN
    CREATE POLICY "Full access pagos_contrato_alumno" 
    ON public.pagos_contrato_alumno FOR ALL 
    TO authenticated 
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;

-- ── PASO 4: Verificación final ─────────────────────────────────────────────

-- Ver todas las tablas y su estado de RLS
SELECT 
  t.tablename,
  t.rowsecurity as rls_habilitado,
  COUNT(p.policyname) as cantidad_politicas
FROM pg_tables t
LEFT JOIN pg_policies p ON t.tablename = p.tablename
WHERE t.schemaname = 'public'
GROUP BY t.tablename, t.rowsecurity
ORDER BY t.rowsecurity, t.tablename;

-- ============================================================================
-- RESULTADO ESPERADO: Todas las tablas deben tener rowsecurity = true
-- y al menos 1 política asociada.
-- ============================================================================
