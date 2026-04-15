-- Arquitectura V4: Argüello Events - Supabase SQL Schema

-- Enum Types
CREATE TYPE rol_usuario AS ENUM ('Admin', 'Asesor');
CREATE TYPE estado_evento AS ENUM ('Planificacion', 'Confirmado', 'Finalizado', 'Cancelado');

-- 1. Perfiles (Vinculado a auth.users de Supabase)
CREATE TABLE public.perfiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  rol rol_usuario DEFAULT 'Asesor' NOT NULL,
  nombre TEXT
);

-- 2. Clientes
CREATE TABLE public.clientes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre_completo TEXT NOT NULL,
  telefono TEXT,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Servicios (Catálogo Estricto)
-- La columna costo_base y margen_ganancia serán gestionadas solo por el Admin
CREATE TABLE public.servicios (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre TEXT NOT NULL UNIQUE,
  costo_base NUMERIC(10, 2) DEFAULT 0.00,
  margen_ganancia NUMERIC(10, 2) DEFAULT 0.00
);

-- Carga inicial estricta (V4)
INSERT INTO public.servicios (nombre) VALUES
  ('Sonido'),
  ('Iluminación'),
  ('Ambientación'),
  ('Escenario'),
  ('Monitoreo'),
  ('Pantallas led'),
  ('Decoración'),
  ('Fotografía'),
  ('Efectos especiales'),
  ('Espejo mágico'),
  ('Estructuras');

-- 4. Eventos
CREATE TABLE public.eventos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  cliente_id UUID REFERENCES public.clientes(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  fecha_evento DATE NOT NULL,
   cantidad_cuotas INTEGER DEFAULT 1,
   modalidad TEXT NOT NULL DEFAULT 'particular',
  estado estado_evento DEFAULT 'Planificacion',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5.bis. Contratos por Alumno (Eventos Masivos)
CREATE TABLE public.contratos_alumnos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  evento_id UUID REFERENCES public.eventos(id) ON DELETE CASCADE,
  nombre_alumno TEXT NOT NULL,
  institucion TEXT,
  cantidad_acompañantes INTEGER DEFAULT 0,
  monto_total_pactado NUMERIC(10, 2) NOT NULL,
  saldo_deudor NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5.ter. Pagos individuales de contrato de alumno
CREATE TABLE public.pagos_contrato_alumno (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  contrato_alumno_id UUID REFERENCES public.contratos_alumnos(id) ON DELETE CASCADE,
  monto NUMERIC(10, 2) NOT NULL,
  fecha_pago TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Eventos_Servicios (Presupuesto Dinámico)
CREATE TABLE public.eventos_servicios (
  evento_id UUID REFERENCES public.eventos(id) ON DELETE CASCADE,
  servicio_id UUID REFERENCES public.servicios(id) ON DELETE CASCADE,
  precio_final_acordado NUMERIC(10, 2) NOT NULL,
  PRIMARY KEY (evento_id, servicio_id)
);

-- 6. Transacciones (Ingresos - Ledger Inmutable)
CREATE TABLE public.transacciones (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  evento_id UUID REFERENCES public.eventos(id) ON DELETE CASCADE,
  monto NUMERIC(10, 2) NOT NULL,
  concepto TEXT,
  fecha_pago TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES public.perfiles(id)
);

-- 7. Egresos (Costos - Ledger Inmutable)
CREATE TABLE public.egresos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  evento_id UUID REFERENCES public.eventos(id) ON DELETE CASCADE,
  monto NUMERIC(10, 2) NOT NULL,
  concepto TEXT,
  fecha_pago TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES public.perfiles(id)
);

-- Funciones y Vistas Requeridas V4

-- Vista: Presupuesto Total por Evento
CREATE VIEW public.vista_presupuesto_total AS
SELECT 
  evento_id,
  SUM(precio_final_acordado) AS presupuesto_total
FROM public.eventos_servicios
GROUP BY evento_id;

-- Vista: Total Ingresos (Transacciones) por Evento
CREATE VIEW public.vista_ingresos_total AS
SELECT
  evento_id,
  SUM(monto) as total_ingresos
FROM public.transacciones
GROUP BY evento_id;

-- Vista: Saldos Dinámicos
CREATE VIEW public.vista_saldos_eventos AS
SELECT 
  e.id AS evento_id,
  COALESCE(p.presupuesto_total, 0) AS presupuesto_total,
  COALESCE(i.total_ingresos, 0) AS total_ingresos,
  (COALESCE(p.presupuesto_total, 0) - COALESCE(i.total_ingresos, 0)) AS saldo_deudor
FROM public.eventos e
LEFT JOIN public.vista_presupuesto_total p ON e.id = p.evento_id
LEFT JOIN public.vista_ingresos_total i ON e.id = i.evento_id;

-- Políticas de Seguridad (RLS)
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Lectura de perfiles propia o admin" ON public.perfiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Usuarios gestionan su propio perfil" ON public.perfiles FOR ALL TO authenticated USING (auth.uid() = id);

ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transacciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.egresos ENABLE ROW LEVEL SECURITY;

-- Todos los autenticados pueden ver servicios (pero la app Flutter filtrará las columnas de costos para Asesores, o se puede usar RLS de columnas en Supabase)
CREATE POLICY "Lectura general de servicios" ON public.servicios FOR SELECT TO authenticated USING (true);
CREATE POLICY "Solo Admin edita servicios" ON public.servicios FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid() AND rol = 'Admin')
);

-- Permitir a usuarios autenticados leer y crear en general (simplificado para MVP inicial)
CREATE POLICY "Full access clientes" ON public.clientes FOR ALL TO authenticated USING (true);
CREATE POLICY "Full access eventos" ON public.eventos FOR ALL TO authenticated USING (true);
CREATE POLICY "Full access eventos_servicios" ON public.eventos_servicios FOR ALL TO authenticated USING (true);
CREATE POLICY "Full access transacciones" ON public.transacciones FOR ALL TO authenticated USING (true);
CREATE POLICY "Full access egresos" ON public.egresos FOR ALL TO authenticated USING (true);
