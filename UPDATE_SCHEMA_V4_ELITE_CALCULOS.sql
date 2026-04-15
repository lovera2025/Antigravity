-- =========================================================================
-- JUNIOR EVENTOS - REPARACIÓN ESTRUCTURAL DE CÁLCULOS Y CATÁLOGO
-- =========================================================================

-- 1. ASEGURAR COLUMNAS DE CANTIDAD Y GRUPO EN TODAS LAS TABLAS
-- En eventos_servicios
ALTER TABLE public.eventos_servicios ADD COLUMN IF NOT EXISTS cantidad NUMERIC DEFAULT 1.0;
ALTER TABLE public.eventos_servicios ADD COLUMN IF NOT EXISTS grupo TEXT;
ALTER TABLE public.eventos_servicios ADD COLUMN IF NOT EXISTS detalle_servicio TEXT;

-- En presupuesto_servicios (la que causaba el error de multiplicación)
ALTER TABLE public.presupuesto_servicios ADD COLUMN IF NOT EXISTS cantidad NUMERIC DEFAULT 1.0;
ALTER TABLE public.presupuesto_servicios ADD COLUMN IF NOT EXISTS grupo TEXT;

-- 2. SOPORTE PARA ARCHIVADO DE SERVICIOS (Soft Delete)
-- Permite quitar servicios del catálogo sin romper presupuestos históricos
ALTER TABLE public.servicios ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- 3. ACTUALIZACIÓN DE VISTAS PARA CÁLCULO REAL (PRECIO * CANTIDAD)
-- Reemplaza la vista que solo sumaba precios sin multiplicar por cantidad

-- Vista: Presupuesto Total por Evento (Corregida)
CREATE OR REPLACE VIEW public.vista_presupuesto_total AS
SELECT 
  evento_id,
  SUM(precio_final_acordado * COALESCE(cantidad, 1)) AS presupuesto_total
FROM public.eventos_servicios
GROUP BY evento_id;

-- Re-crear vista de saldos para que tome el nuevo cálculo
CREATE OR REPLACE VIEW public.vista_saldos_eventos AS
SELECT 
  e.id AS evento_id,
  COALESCE(p.presupuesto_total, 0) AS presupuesto_total,
  COALESCE(i.total_ingresos, 0) AS total_ingresos,
  (COALESCE(p.presupuesto_total, 0) - COALESCE(i.total_ingresos, 0)) AS saldo_deudor
FROM public.eventos e
LEFT JOIN public.vista_presupuesto_total p ON e.id = p.evento_id
LEFT JOIN public.vista_ingresos_total i ON e.id = i.evento_id;

-- 4. COMENTARIO DE ÉXITO
-- Estos cambios aseguran que 150 piezas x 15.000 se vea como 2.250.000
-- y que se puedan "borrar" servicios del catálogo sin errores rojos.
