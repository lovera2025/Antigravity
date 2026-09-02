-- 2026-09-02 — Bajar el consumo de Disk IO del proyecto Supabase.
--
-- Supabase avisó que ArguelloApp estaba agotando su Disk IO Budget. La medición
-- de pg_stat_statements mostró que realtime.apply_rls (el "SELECT wal->>...")
-- se llevaba el 89,5% del CPU de la base y el 99,7% de los bloques leídos:
-- 10.148.455 llamadas, una de cuyas variantes hizo 3.137.112 consultas para
-- devolver 138 filas. Realtime consulta el slot de replicación cada 100 ms
-- mientras haya un cliente conectado, haya o no cambios, y eso lee segmentos de
-- WAL crudos salteando la caché. El costo por llamada escala con la cantidad de
-- suscripciones vivas, y la app abría ~20 sin filtro por PC.
--
-- Casi todo era redundante: OperationalSyncCoordinator ya baja esas mismas
-- tablas cada 10 segundos.

-- ── 1. La publicación queda solo con invitados ──────────────────────────────
--
-- invitados se queda porque es el tótem: ahí alguien está parado en la puerta
-- esperando el check-in, y es el único lugar donde la latencia de Realtime se
-- justifica. El resto pasa a depender del pull incremental.
--
-- Reversible: alter publication supabase_realtime add table <tabla>;

alter publication supabase_realtime drop table
  contratos_alumnos,
  pagos_contrato_alumno,
  egresos,
  pagos_prestamo_alquiler,
  transacciones,
  solicitudes_cotizacion;

-- ── 2. Índices sobre updated_at ─────────────────────────────────────────────
--
-- El pull incremental filtra y ordena por updated_at, pero solo tres tablas
-- tenían el índice. pagos_contrato_alumno acumulaba 43.030 seq scans y 96
-- millones de tuplas leídas sobre 3.066 filas.
--
-- Sin CONCURRENTLY a propósito: la tabla más grande pesa 776 kB, así que el
-- lock dura milisegundos y esto puede correr dentro de una transacción.

create index if not exists idx_contratos_alumnos_updated
  on public.contratos_alumnos (updated_at desc);

create index if not exists idx_pagos_contrato_alumno_updated
  on public.pagos_contrato_alumno (updated_at desc);

create index if not exists idx_egresos_updated
  on public.egresos (updated_at desc);

create index if not exists idx_sesiones_caja_updated
  on public.sesiones_caja (updated_at desc);

create index if not exists idx_operadores_caja_updated
  on public.operadores_caja (updated_at desc);

create index if not exists idx_eventos_updated
  on public.eventos (updated_at desc);

create index if not exists idx_clientes_updated
  on public.clientes (updated_at desc);

create index if not exists idx_transacciones_updated
  on public.transacciones (updated_at desc);

-- Las tablas que el pull ampliado suma en esta misma tanda.
create index if not exists idx_eventos_servicios_updated
  on public.eventos_servicios (updated_at desc);

create index if not exists idx_servicios_updated
  on public.servicios (updated_at desc);

create index if not exists idx_presupuestos_updated
  on public.presupuestos (updated_at desc);

create index if not exists idx_presupuesto_servicios_updated
  on public.presupuesto_servicios (updated_at desc);

create index if not exists idx_solicitudes_cotizacion_updated
  on public.solicitudes_cotizacion (updated_at desc);
