-- Préstamo / alquiler de ítems (sillas, mesas, etc.) — sincronizado con app desktop

CREATE TABLE IF NOT EXISTS public.prestamos_alquiler (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  fecha_inicio TIMESTAMPTZ NOT NULL,
  fecha_fin TIMESTAMPTZ NOT NULL,
  aplica_iva BOOLEAN NOT NULL DEFAULT false,
  alicuota_iva NUMERIC(6, 2) NOT NULL DEFAULT 21,
  subtotal_neto NUMERIC(12, 2) NOT NULL DEFAULT 0,
  monto_iva NUMERIC(12, 2) NOT NULL DEFAULT 0,
  total NUMERIC(12, 2) NOT NULL DEFAULT 0,
  texto_redaccion TEXT,
  texto_disclaimer TEXT,
  visible_listado BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.prestamo_alquiler_lineas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prestamo_id UUID NOT NULL REFERENCES public.prestamos_alquiler(id) ON DELETE CASCADE,
  descripcion TEXT NOT NULL,
  cantidad NUMERIC(12, 2) NOT NULL,
  precio_unitario NUMERIC(12, 2) NOT NULL,
  linea_total NUMERIC(12, 2) NOT NULL,
  orden INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.pagos_prestamo_alquiler (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prestamo_id UUID NOT NULL REFERENCES public.prestamos_alquiler(id) ON DELETE CASCADE,
  monto NUMERIC(12, 2) NOT NULL,
  concepto TEXT,
  fecha_pago TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prestamos_alquiler_cliente ON public.prestamos_alquiler(cliente_id);
CREATE INDEX IF NOT EXISTS idx_prestamos_alquiler_visible ON public.prestamos_alquiler(visible_listado);
CREATE INDEX IF NOT EXISTS idx_lineas_prestamo ON public.prestamo_alquiler_lineas(prestamo_id);
CREATE INDEX IF NOT EXISTS idx_pagos_prestamo ON public.pagos_prestamo_alquiler(prestamo_id);

ALTER TABLE public.prestamos_alquiler ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prestamo_alquiler_lineas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos_prestamo_alquiler ENABLE ROW LEVEL SECURITY;

-- Ajustar según políticas existentes del proyecto (mismo patrón que otras tablas de negocio)
CREATE POLICY "prestamos_alquiler_all_authenticated" ON public.prestamos_alquiler
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "prestamo_lineas_all_authenticated" ON public.prestamo_alquiler_lineas
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "pagos_prestamo_all_authenticated" ON public.pagos_prestamo_alquiler
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
