-- 1. Asegurar nombres sin ñ para consistencia con SQLite y el nuevo Modelo
ALTER TABLE public.contratos_alumnos ADD COLUMN IF NOT EXISTS cantidad_acompanantes INTEGER DEFAULT 0;
ALTER TABLE public.contratos_alumnos ADD COLUMN IF NOT EXISTS nombres_acompanantes JSONB DEFAULT '[]';

-- 2. Añadir campo de Número de Mesa
ALTER TABLE public.contratos_alumnos ADD COLUMN IF NOT EXISTS numero_mesa TEXT;

-- 3. (Opcional) Migrar datos si existen en las columnas con ñ (si Supabase las creó antes)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='contratos_alumnos' AND column_name='cantidad_acompañantes') THEN
        UPDATE public.contratos_alumnos SET cantidad_acompanantes = cantidad_acompañantes WHERE cantidad_acompanantes = 0;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='contratos_alumnos' AND column_name='nombres_acompañantes') THEN
        UPDATE public.contratos_alumnos SET nombres_acompanantes = nombres_acompañantes WHERE nombres_acompanantes = '[]'::jsonb;
    END IF;
END $$;
