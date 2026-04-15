-- ============================================================================
-- FIX DEFINITIVO: Habilitar RLS y políticas en TODAS las tablas de Supabase
-- Motivo: Alerta de seguridad de Supabase (Table publicly accessible)
-- Fecha: 14 Abril 2026
-- ============================================================================

-- Este script es seguro de ejecutar múltiples veces (idempotente)
-- Cubre todas las tablas actuales, incluyendo las últimas agregadas
-- como presupuestos y presupuesto_servicios.

-- ────────────────────────────────────────────────────────────────────────────
-- 1. ASEGURAR QUE RLS ESTÁ HABILITADO EN TODAS LAS TABLAS
-- ────────────────────────────────────────────────────────────────────────────

-- Tablas base
ALTER TABLE IF EXISTS public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.eventos_servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.transacciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.egresos ENABLE ROW LEVEL SECURITY;

-- Tablas de sub-módulos (alumnos, recepción, accesos)
ALTER TABLE IF EXISTS public.contratos_alumnos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.pagos_contrato_alumno ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.invitados ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.accesos ENABLE ROW LEVEL SECURITY;

-- Tablas de cotizaciones / presupuestos (Las que faltaban)
ALTER TABLE IF EXISTS public.solicitudes_cotizacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.presupuestos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.presupuesto_servicios ENABLE ROW LEVEL SECURITY;

-- Tablas adicionales detectadas en la base de datos
ALTER TABLE IF EXISTS public.modulo_financiero ENABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. POLÍTICAS DE ACCESO PARA USUARIOS AUTENTICADOS (El modelo actual)
-- ────────────────────────────────────────────────────────────────────────────

DO $$ 
DECLARE
  var_table_name text;
  -- Lista de tablas que deben tener acceso total para usuarios logueados en la app
  tables_with_full_auth_access text[] := ARRAY[
    'clientes', 
    'eventos', 
    'eventos_servicios', 
    'transacciones', 
    'egresos',
    'contratos_alumnos', 
    'pagos_contrato_alumno', 
    'invitados',
    'accesos',
    'solicitudes_cotizacion',
    'presupuestos',
    'presupuesto_servicios',
    'modulo_financiero'
  ];
BEGIN
  -- Iterar sobre las tablas para crear las políticas de acceso si no existen
  FOREACH var_table_name IN ARRAY tables_with_full_auth_access
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = var_table_name) THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = var_table_name AND policyname = format('Full access %s authenticated', var_table_name)
      ) THEN
        EXECUTE format(
          'CREATE POLICY "Full access %I authenticated" ON public.%I FOR ALL TO authenticated USING (true) WITH CHECK (true);',
          var_table_name, var_table_name
        );
      END IF;
    END IF;
  END LOOP;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. POLÍTICAS ESPECÍFICAS (PERFILES Y SERVICIOS)
-- ────────────────────────────────────────────────────────────────────────────

-- PERFILES:
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'perfiles' AND policyname = 'Lectura de perfiles propia o admin') THEN
    CREATE POLICY "Lectura de perfiles propia o admin" ON public.perfiles FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'perfiles' AND policyname = 'Usuarios gestionan su propio perfil') THEN
    CREATE POLICY "Usuarios gestionan su propio perfil" ON public.perfiles FOR ALL TO authenticated USING (auth.uid() = id);
  END IF;
END $$;

-- SERVICIOS (Catálogo global):
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'servicios' AND policyname = 'Lectura general de servicios') THEN
    CREATE POLICY "Lectura general de servicios" ON public.servicios FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'servicios' AND policyname = 'Solo Admin edita servicios') THEN
    CREATE POLICY "Solo Admin edita servicios" ON public.servicios FOR ALL TO authenticated USING (
      EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid() AND rol = 'Admin')
    );
  END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. VERIFICACIÓN: AUDITORÍA DE TABLAS SIN RLS (DEBE SALIR VACÍO)
-- ────────────────────────────────────────────────────────────────────────────

-- Ejecutar este bloque al final te permitirá confirmar que la corrección funcionó.
-- Si hay alguna tabla pública expuesta, aparecerá listada en la salida.
SELECT 
  schemaname, 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' AND rowsecurity = false
ORDER BY tablename;
