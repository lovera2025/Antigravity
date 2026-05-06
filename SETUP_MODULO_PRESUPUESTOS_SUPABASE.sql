-- =========================================================================
-- JUNIOR EVENTOS - CONFIGURACIÓN DEL MÓDULO DE PRESUPUESTOS (SUPABASE)
-- =========================================================================

-- 1. ACTUALIZACIÓN DEL CATÁLOGO DE SERVICIOS
-- Añade categorización y costos internos para presupuestos de élite
ALTER TABLE public.servicios ADD COLUMN IF NOT EXISTS categoria TEXT DEFAULT 'General';
ALTER TABLE public.servicios ADD COLUMN IF NOT EXISTS costo_interno NUMERIC DEFAULT 0;

-- 2. CREACIÓN DE LA TABLA DE PRESUPUESTOS
-- Registra la propuesta comercial antes de convertirse en evento real
CREATE TABLE IF NOT EXISTS public.presupuestos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id UUID NOT NULL REFERENCES public.clientes(id),
    tipo_evento TEXT NOT NULL,
    lugar TEXT,
    detalle_anclaje TEXT,
    fecha_vencimiento TIMESTAMPTZ NOT NULL,
    estado TEXT DEFAULT 'activo' CHECK (estado IN ('activo', 'vencido', 'confirmado')),
    instagram TEXT,
    telefono TEXT,
    notificado_vencimiento BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREACIÓN DE LA TABLA DE SERVICIOS VINCULADOS AL PRESUPUESTO
-- PK id por línea (sync / app); permite varias líneas con el mismo servicio_id (combos, etc.).
-- Si ya tenés la tabla vieja con PK compuesta, aplicá supabase/migrations/20260422120000_presupuesto_servicios_line_id.sql
CREATE TABLE IF NOT EXISTS public.presupuesto_servicios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    presupuesto_id UUID NOT NULL REFERENCES public.presupuestos(id) ON DELETE CASCADE,
    servicio_id UUID NOT NULL REFERENCES public.servicios(id),
    precio_final NUMERIC NOT NULL,
    cantidad NUMERIC DEFAULT 1.0,
    grupo TEXT,
    combo_orden INTEGER DEFAULT 0,
    detalle_servicio TEXT
);

-- 4. CONFIGURACIÓN DE SEGURIDAD (RLS)
ALTER TABLE public.presupuestos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.presupuesto_servicios ENABLE ROW LEVEL SECURITY;

-- Nota: Estas políticas permiten a los usuarios autenticados gestionar presupuestos.
-- Ajustar si se requiere mayor restricción por roles específicos.
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Permitir gestión completa a autenticados' AND tablename = 'presupuestos') THEN
        CREATE POLICY "Permitir gestión completa a autenticados" ON public.presupuestos
            FOR ALL USING (auth.role() = 'authenticated');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Permitir gestión completa a autenticados' AND tablename = 'presupuesto_servicios') THEN
        CREATE POLICY "Permitir gestión completa a autenticados" ON public.presupuesto_servicios
            FOR ALL USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- 5. ÍNDICES PARA OPTIMIZACIÓN
CREATE INDEX IF NOT EXISTS idx_presupuestos_cliente ON public.presupuestos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_presupuestos_estado ON public.presupuestos(estado);
CREATE INDEX IF NOT EXISTS idx_presupuesto_servicios_presupuesto ON public.presupuesto_servicios (presupuesto_id);
