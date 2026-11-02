-- ============================================================================
-- Registro de cada cambio a la mora de un alumno, en la nube.
--
-- Pedido del usuario el 2-nov-2026: la idea es que una mora cobrada o
-- perdonada NO reviva. Cada caso hasta hoy se descubrió cuando la familia
-- reclamó, sin saber qué PC lo escribió ni cuándo. Con este registro, el
-- próximo caso trae su huella: qué campo cambió, de qué valor a cuál, a qué
-- hora, y qué más pasó alrededor (un cobro, una edición, la revisión del
-- arranque). Con eso se cierra en el código, con su test, sin adivinar.
--
-- Qué hace: un trigger AFTER UPDATE en contratos_alumnos que anota una fila
-- en mora_cambios SOLO cuando cambia alguno de los campos de la mora. No toca
-- la fila del alumno, no cambia ningún valor y NUNCA frena la escritura: si
-- por lo que sea no puede anotar, deja pasar el UPDATE igual (EXCEPTION ...
-- THEN NULL). La app no conoce la tabla: no se sincroniza y no tiene políticas
-- (solo el rol de servicio la lee).
--
-- ROLLBACK (saca el trigger y la función; la tabla se puede dejar):
--   drop trigger if exists contratos_alumnos_mora_cambios on public.contratos_alumnos;
--   drop function if exists public.anotar_cambio_de_mora();
--   -- drop table if exists public.mora_cambios;
-- ============================================================================

-- ── 1. La tabla ────────────────────────────────────────────────────────────

create table if not exists public.mora_cambios (
  id                     bigserial primary key,
  cambiado_at            timestamptz not null default now(),
  contrato_alumno_id     uuid        not null,
  evento_id              uuid,
  nombre_alumno          text,
  -- antes → después, solo de lo que cambió (lo igual queda null en los dos)
  mora_pendiente_tracked_antes   double precision,
  mora_pendiente_tracked_despues double precision,
  mora_tracked_ajuste_antes      double precision,
  mora_tracked_ajuste_despues    double precision,
  mora_cobrada_offset_antes      double precision,
  mora_cobrada_offset_despues    double precision,
  mora_exenta_hasta_antes        date,
  mora_exenta_hasta_despues      date,
  mora_exencion_reinicia_antes   smallint,
  mora_exencion_reinicia_despues smallint,
  mora_fecha_referencia_antes    date,
  mora_fecha_referencia_despues  date,
  saldo_deudor_antes             numeric,
  saldo_deudor_despues           numeric,
  -- qué más trajo la escritura, para ubicar el camino: si cambió el saldo es
  -- un cobro o un recálculo; si cambió otra cosa de la ficha, una edición
  otras_columnas_cambiadas       text[],
  -- quién escribió, lo que PostgREST deja ver (el usuario y el cliente)
  usuario                        text,
  cliente                        text,
  updated_at_antes               timestamptz,
  updated_at_despues             timestamptz
);

create index if not exists mora_cambios_alumno_idx on public.mora_cambios (contrato_alumno_id, cambiado_at);
create index if not exists mora_cambios_fecha_idx  on public.mora_cambios (cambiado_at);

alter table public.mora_cambios enable row level security;

-- ── 2. La función y el trigger ─────────────────────────────────────────────

create or replace function public.anotar_cambio_de_mora()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  otras text[] := '{}';
  hdr   jsonb;
begin
  -- Solo si cambió algo de la mora (o el saldo, que va con ella).
  if old.mora_pendiente_tracked is not distinct from new.mora_pendiente_tracked
     and old.mora_tracked_ajuste    is not distinct from new.mora_tracked_ajuste
     and old.mora_cobrada_offset    is not distinct from new.mora_cobrada_offset
     and old.mora_exenta_hasta      is not distinct from new.mora_exenta_hasta
     and old.mora_exencion_reinicia is not distinct from new.mora_exencion_reinicia
     and old.mora_fecha_referencia  is not distinct from new.mora_fecha_referencia
  then
    return new;
  end if;

  begin
    -- Qué otras columnas vinieron cambiadas en la misma escritura.
    select coalesce(array_agg(k order by k), '{}')
      into otras
      from jsonb_each(to_jsonb(new)) n(k, v)
      join jsonb_each(to_jsonb(old)) o(k, v) using (k)
     where n.v is distinct from o.v
       and k not in ('mora_pendiente_tracked', 'mora_tracked_ajuste', 'mora_cobrada_offset',
                     'mora_exenta_hasta', 'mora_exencion_reinicia', 'mora_fecha_referencia',
                     'updated_at');

    begin
      hdr := current_setting('request.headers', true)::jsonb;
    exception when others then
      hdr := null;
    end;

    insert into public.mora_cambios (
      contrato_alumno_id, evento_id, nombre_alumno,
      mora_pendiente_tracked_antes, mora_pendiente_tracked_despues,
      mora_tracked_ajuste_antes,    mora_tracked_ajuste_despues,
      mora_cobrada_offset_antes,    mora_cobrada_offset_despues,
      mora_exenta_hasta_antes,      mora_exenta_hasta_despues,
      mora_exencion_reinicia_antes, mora_exencion_reinicia_despues,
      mora_fecha_referencia_antes,  mora_fecha_referencia_despues,
      saldo_deudor_antes,           saldo_deudor_despues,
      otras_columnas_cambiadas, usuario, cliente,
      updated_at_antes, updated_at_despues
    ) values (
      new.id, new.evento_id, new.nombre_alumno,
      case when old.mora_pendiente_tracked is distinct from new.mora_pendiente_tracked then old.mora_pendiente_tracked end,
      case when old.mora_pendiente_tracked is distinct from new.mora_pendiente_tracked then new.mora_pendiente_tracked end,
      case when old.mora_tracked_ajuste    is distinct from new.mora_tracked_ajuste    then old.mora_tracked_ajuste end,
      case when old.mora_tracked_ajuste    is distinct from new.mora_tracked_ajuste    then new.mora_tracked_ajuste end,
      case when old.mora_cobrada_offset    is distinct from new.mora_cobrada_offset    then old.mora_cobrada_offset end,
      case when old.mora_cobrada_offset    is distinct from new.mora_cobrada_offset    then new.mora_cobrada_offset end,
      case when old.mora_exenta_hasta      is distinct from new.mora_exenta_hasta      then old.mora_exenta_hasta end,
      case when old.mora_exenta_hasta      is distinct from new.mora_exenta_hasta      then new.mora_exenta_hasta end,
      case when old.mora_exencion_reinicia is distinct from new.mora_exencion_reinicia then old.mora_exencion_reinicia end,
      case when old.mora_exencion_reinicia is distinct from new.mora_exencion_reinicia then new.mora_exencion_reinicia end,
      case when old.mora_fecha_referencia  is distinct from new.mora_fecha_referencia  then old.mora_fecha_referencia end,
      case when old.mora_fecha_referencia  is distinct from new.mora_fecha_referencia  then new.mora_fecha_referencia end,
      case when old.saldo_deudor           is distinct from new.saldo_deudor           then old.saldo_deudor end,
      case when old.saldo_deudor           is distinct from new.saldo_deudor           then new.saldo_deudor end,
      otras,
      coalesce(auth.jwt() ->> 'email', current_user::text),
      coalesce(hdr ->> 'x-client-info', hdr ->> 'user-agent'),
      old.updated_at, new.updated_at
    );
  exception when others then
    -- Anotar nunca puede costar un cobro: si falla, la escritura sigue.
    null;
  end;

  return new;
end;
$$;

drop trigger if exists contratos_alumnos_mora_cambios on public.contratos_alumnos;
create trigger contratos_alumnos_mora_cambios
  after update on public.contratos_alumnos
  for each row
  execute function public.anotar_cambio_de_mora();

-- ── 3. Cómo se lee ─────────────────────────────────────────────────────────

-- Todo lo que cambió de la mora desde una fecha (por ejemplo, desde que se
-- instaló una versión), lo más nuevo primero:
-- select cambiado_at at time zone 'America/Argentina/Buenos_Aires' as cuando,
--        nombre_alumno, usuario, cliente, otras_columnas_cambiadas,
--        mora_pendiente_tracked_antes, mora_pendiente_tracked_despues,
--        mora_tracked_ajuste_antes,    mora_tracked_ajuste_despues,
--        mora_cobrada_offset_antes,    mora_cobrada_offset_despues,
--        mora_exenta_hasta_antes,      mora_exenta_hasta_despues,
--        saldo_deudor_antes,           saldo_deudor_despues
-- from public.mora_cambios
-- where cambiado_at >= '2026-11-02'
-- order by cambiado_at desc;

-- La historia de un alumno:
-- select * from public.mora_cambios
-- where contrato_alumno_id = '<id>'
-- order by cambiado_at;

-- Las "revividas": la mora pendiente subió, o se fue una eximición, o se fue
-- un perdón, sin que en la misma escritura cambiara el saldo (no fue un cobro):
-- select cambiado_at at time zone 'America/Argentina/Buenos_Aires' as cuando,
--        nombre_alumno, usuario, otras_columnas_cambiadas,
--        mora_pendiente_tracked_antes, mora_pendiente_tracked_despues,
--        mora_exenta_hasta_antes, mora_exenta_hasta_despues,
--        mora_tracked_ajuste_antes, mora_tracked_ajuste_despues
-- from public.mora_cambios
-- where saldo_deudor_despues is null
--   and (coalesce(mora_pendiente_tracked_despues, 0) > coalesce(mora_pendiente_tracked_antes, 0)
--        or (mora_exenta_hasta_antes is not null and mora_exenta_hasta_despues is null)
--        or (coalesce(mora_tracked_ajuste_antes, 0) <> 0 and coalesce(mora_tracked_ajuste_despues, 0) = 0))
-- order by cambiado_at desc;

-- ── Verificación ───────────────────────────────────────────────────────────
-- select tgname, tgenabled from pg_trigger where tgrelid = 'public.contratos_alumnos'::regclass;
-- Tiene que aparecer contratos_alumnos_mora_cambios, habilitado ('O').
-- Y una prueba que no cambia nada: un UPDATE de una columna que no es de la
-- mora no tiene que anotar ninguna fila.
