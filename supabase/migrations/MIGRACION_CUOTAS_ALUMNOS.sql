-- MIGRACIÓN: Cuotas dinámicas para alumnos
-- Ejecutar en el SQL Editor de Supabase

ALTER TABLE public.contratos_alumnos
ADD COLUMN IF NOT EXISTS cuotas_pagadas INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_cuotas INTEGER DEFAULT 9,
ADD COLUMN IF NOT EXISTS dia_vencimiento_mensual INTEGER DEFAULT 10;

-- Asegurar columna created_at en tabla de pagos (para auditoría estándar)
ALTER TABLE public.pagos_contrato_alumno
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Comentario para auditoría
COMMENT ON COLUMN public.contratos_alumnos.cuotas_pagadas IS 'Cantidad de cuotas ya abonadas por el alumno';
COMMENT ON COLUMN public.contratos_alumnos.total_cuotas IS 'Plan total de cuotas pactado (ej: 9 cuotas)';
COMMENT ON COLUMN public.contratos_alumnos.dia_vencimiento_mensual IS 'Día del mes establecido como límite de pago (default 10)';
COMMENT ON COLUMN public.pagos_contrato_alumno.created_at IS 'Fecha de creación del registro de pago';
