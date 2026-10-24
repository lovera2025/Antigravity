CREATE OR REPLACE FUNCTION obtener_proyeccion_financiera()
RETURNS TABLE (
  capital_liquido NUMERIC,
  opex_capex_a_30_dias NUMERIC,
  proyeccion_caja_30d NUMERIC,
  estado_sistema TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  tot_particulares NUMERIC := 0;
  tot_masivos NUMERIC := 0;
  tot_egresos NUMERIC := 0;
  egresos_30d NUMERIC := 0;
  cap_liquido NUMERIC := 0;
  proy_30 NUMERIC := 0;
  estado TEXT := 'SALUDABLE';
BEGIN
  -- 1. Ingresos Totales Históricos (Particulares + Masivos)
  SELECT COALESCE(SUM(monto), 0) INTO tot_particulares FROM transacciones;
  SELECT COALESCE(SUM(monto), 0) INTO tot_masivos FROM pagos_contrato_alumno;
  
  -- 2. Egresos Totales Históricos
  SELECT COALESCE(SUM(monto), 0) INTO tot_egresos FROM egresos;
  
  -- Calcular Capital Líquido
  cap_liquido := (tot_particulares + tot_masivos) - tot_egresos;

  -- 3. OPEX/CAPEX a 30 días (Promedio de egresos de los últimos 30 días)
  SELECT COALESCE(SUM(monto), 0) INTO egresos_30d 
  FROM egresos 
  WHERE fecha >= CURRENT_DATE - INTERVAL '30 days';

  -- 4. Proyección de Caja a 30 Días
  -- Calculado como el Capital actual menos los gastos esperados para los próximos 30 días
  proy_30 := cap_liquido - egresos_30d;

  -- 5. Semáforo de Salud Sistémica
  IF proy_30 < 0 THEN
    estado := 'CRÍTICO: RIESGO DE INSOLVENCIA';
  ELSIF proy_30 < (cap_liquido * 0.2) AND cap_liquido > 0 THEN
    estado := 'ADVERTENCIA: LIQUIDEZ BAJA';
  ELSE
    estado := 'SALUDABLE: FLUZ DE CAJA POSITIVO';
  END IF;

  RETURN QUERY SELECT cap_liquido, egresos_30d, proy_30, estado;
END;
$$;
