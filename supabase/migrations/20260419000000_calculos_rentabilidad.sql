-- Cálculos de rentabilidad (P&L por evento/presupuesto) — sincronizado entre dispositivos

CREATE TABLE IF NOT EXISTS public.calculos_rentabilidad (
  id UUID PRIMARY KEY,
  evento_id UUID REFERENCES public.eventos(id) ON DELETE SET NULL,
  presupuesto_id UUID REFERENCES public.presupuestos(id) ON DELETE SET NULL,
  precio_venta NUMERIC(14, 2) NOT NULL DEFAULT 0,
  honorario_adrian_monto NUMERIC(14, 2) NOT NULL DEFAULT 0,
  honorario_adrian_pct NUMERIC(10, 4) NOT NULL DEFAULT 0,
  honorario_modo TEXT NOT NULL DEFAULT 'monto',
  costos_variables_json TEXT,
  costos_fijos_json TEXT,
  resultado NUMERIC(14, 2),
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_calculos_rentabilidad_created ON public.calculos_rentabilidad(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calculos_rentabilidad_evento ON public.calculos_rentabilidad(evento_id);
CREATE INDEX IF NOT EXISTS idx_calculos_rentabilidad_presupuesto ON public.calculos_rentabilidad(presupuesto_id);

ALTER TABLE public.calculos_rentabilidad ENABLE ROW LEVEL SECURITY;

CREATE POLICY "calculos_rentabilidad_all_authenticated" ON public.calculos_rentabilidad
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
