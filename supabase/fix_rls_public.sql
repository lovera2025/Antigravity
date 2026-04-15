-- Protocolo de Corrección RLS: Acceso Público para Selección y Solicitudes
-- Ejecutar este script en la consola de Supabase (SQL Editor)

-- 1. Asegurar que la tabla 'solicitudes_cotizacion' exista
CREATE TABLE IF NOT EXISTS public.solicitudes_cotizacion (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  cliente_nombre TEXT NOT NULL,
  cliente_celular TEXT NOT NULL,
  servicios_seleccionados JSONB DEFAULT '[]'::jsonb,
  estado TEXT DEFAULT 'pendiente',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Habilitar RLS en 'solicitudes_cotizacion'
ALTER TABLE public.solicitudes_cotizacion ENABLE ROW LEVEL SECURITY;

-- 3. Políticas para 'servicios' (Lectura pública para el catálogo QR)
DROP POLICY IF EXISTS "Lectura pública de servicios" ON public.servicios;
CREATE POLICY "Lectura pública de servicios" 
ON public.servicios FOR SELECT 
TO anon 
USING (true);

-- 4. Políticas para 'solicitudes_cotizacion' (Inserción pública desde la web)
DROP POLICY IF EXISTS "Inserción pública de solicitudes" ON public.solicitudes_cotizacion;
CREATE POLICY "Inserción pública de solicitudes" 
ON public.solicitudes_cotizacion FOR INSERT 
TO anon 
WITH CHECK (true);

-- 5. Politica para que los Admin/Asesores puedan ver las solicitudes en el Dashboard
DROP POLICY IF EXISTS "Lectura de solicitudes para personal" ON public.solicitudes_cotizacion;
CREATE POLICY "Lectura de solicitudes para personal" 
ON public.solicitudes_cotizacion FOR SELECT 
TO authenticated 
USING (true);

DROP POLICY IF EXISTS "Eliminar solicitudes para personal" ON public.solicitudes_cotizacion;
CREATE POLICY "Eliminar solicitudes para personal"
ON public.solicitudes_cotizacion FOR DELETE
TO authenticated
USING (true);

-- 6.bis. Politica para que el personal pueda marcar como gestionada (actualizar estado)
DROP POLICY IF EXISTS "Actualizar solicitudes para personal" ON public.solicitudes_cotizacion;
CREATE POLICY "Actualizar solicitudes para personal"
ON public.solicitudes_cotizacion FOR UPDATE
TO authenticated
USING (true);

-- 7. Garantizar permisos en el esquema public para anon si ha habido cambios en el rol
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON public.servicios TO anon;
GRANT INSERT ON public.solicitudes_cotizacion TO anon;
GRANT UPDATE, DELETE ON public.solicitudes_cotizacion TO authenticated;
