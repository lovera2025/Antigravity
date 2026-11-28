-- ============================================================================
-- Registro de cada cambio de mesas adicionales o sillas extra de un alumno, en
-- la nube.
--
-- Pedido del usuario el 27-nov-2026: el descuento de las entradas es solo para
-- la mesa adicional y las sillas que la familia ya tenía CARGADAS al sorteo
-- (no importa cuándo las pagó). El programa lo sabe comparando lo de hoy con lo
-- anotado al sortear; lo que faltaba era algo "verificable, más confiable": el
-- día y la hora en que se cargó cada cosa, para cuando una familia reclame.
--
-- Qué hace: un trigger AFTER INSERT OR UPDATE en contratos_alumnos que anota
-- una fila en lugares_cambios SOLO cuando cambia la cantidad o el precio de las
-- mesas adicionales o de las sillas extra (o cuando un alumno se carga ya con
-- algo de eso). Anota los cuatro valores, antes y después. No toca la fila del
-- alumno, no cambia ningún valor y NUNCA frena la escritura: si por lo que sea
-- no puede anotar, deja pasar el INSERT o el UPDATE igual (EXCEPTION ... THEN
-- NULL). La app no conoce la tabla: no se sincroniza y no tiene políticas (solo
-- el rol de servicio la lee). Vale para todas las PCs y todas las versiones.
--
-- Por qué también el precio: el programa cuenta una silla extra solo si tiene
-- precio (`SalonMesas.sillasExtra`), y la mesa adicional sale del precio si la
-- cantidad viene vacía. Un cambio de precio de 0 a algo es "se cargó".
--
-- Solo agrega: una tabla, una función y un trigger nuevos. No cambia nada de
-- lo que hay.
--
-- ROLLBACK (saca el trigger y la función; la tabla se puede dejar):
--   drop trigger if exists contratos_alumnos_lugares_cambios on public.contratos_alumnos;
--   drop function if exists public.anotar_cambio_de_lugares();
--   -- drop table if exists public.lugares_cambios;
-- ============================================================================

-- ── 0. Antes de correrlo: los conteos (tienen que dar igual después) ────────
-- select (select count(*) from public.contratos_alumnos) as alumnos,
--        (select count(*) from public.mora_cambios)      as mora_cambios,
--        (select count(*) from pg_trigger
--          where tgrelid = 'public.contratos_alumnos'::regclass and not tgisinternal) as triggers;
-- Después: alumnos y mora_cambios iguales; triggers, uno más.

-- ── 1. La tabla ────────────────────────────────────────────────────────────

create table if not exists public.lugares_cambios (
  id                               bigserial primary key,
  cambiado_at                      timestamptz not null default now(),
  contrato_alumno_id               uuid        not null,
  evento_id                        uuid,
  nombre_alumno                    text,
  -- 'insert': el alumno se cargó ya con mesa adicional o sillas (los "antes"
  -- quedan en null). 'update': cambió algo de eso.
  operacion                        text,
  mesa_extra_cantidad_antes        integer,
  mesa_extra_cantidad_despues      integer,
  mesa_extra_precio_antes          double precision,
  mesa_extra_precio_despues        double precision,
  sillas_extra_cantidad_antes      integer,
  sillas_extra_cantidad_despues    integer,
  sillas_extra_precio_total_antes  double precision,
  sillas_extra_precio_total_despues double precision,
  -- Las mesas que tenía anotadas en ese momento (el sorteo, o la mesa que el
  -- programa le dio al cargarla).
  numero_mesa                      text,
  -- qué más trajo la escritura, para ubicar el camino (una edición de la
  -- ficha, un cobro, la mesa que se da sola)
  otras_columnas_cambiadas         text[],
  -- quién escribió, lo que PostgREST deja ver (el usuario y el cliente)
  usuario                          text,
  cliente                          text,
  updated_at_antes                 timestamptz,
  updated_at_despues               timestamptz
);

create index if not exists lugares_cambios_alumno_idx on public.lugares_cambios (contrato_alumno_id, cambiado_at);
create index if not exists lugares_cambios_evento_idx on public.lugares_cambios (evento_id, cambiado_at);

alter table public.lugares_cambios enable row level security;

-- ── 2. La función y el trigger ─────────────────────────────────────────────

create or replace function public.anotar_cambio_de_lugares()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  otras text[] := '{}';
  hdr   jsonb;
begin
  -- Todo adentro de un bloque: anotar nunca puede costar una escritura.
  begin
    if tg_op = 'INSERT' then
      -- Un alumno nuevo sin nada de más no deja fila.
      if coalesce(new.mesa_extra_cantidad, 0) <= 0
         and coalesce(new.mesa_extra_precio, 0) <= 0
         and coalesce(new.sillas_extra_cantidad, 0) <= 0
         and coalesce(new.sillas_extra_precio_total, 0) <= 0
      then
        return new;
      end if;
    else
      -- Solo si cambió algo de las mesas adicionales o de las sillas.
      if old.mesa_extra_cantidad       is not distinct from new.mesa_extra_cantidad
         and old.mesa_extra_precio         is not distinct from new.mesa_extra_precio
         and old.sillas_extra_cantidad     is not distinct from new.sillas_extra_cantidad
         and old.sillas_extra_precio_total is not distinct from new.sillas_extra_precio_total
      then
        return new;
      end if;

      -- Qué otras columnas vinieron cambiadas en la misma escritura.
      select coalesce(array_agg(k order by k), '{}')
        into otras
        from jsonb_each(to_jsonb(new)) n(k, v)
        join jsonb_each(to_jsonb(old)) o(k, v) using (k)
       where n.v is distinct from o.v
         and k not in ('mesa_extra_cantidad', 'mesa_extra_precio',
                       'sillas_extra_cantidad', 'sillas_extra_precio_total',
                       'updated_at');
    end if;

    begin
      hdr := current_setting('request.headers', true)::jsonb;
    exception when others then
      hdr := null;
    end;

    insert into public.lugares_cambios (
      contrato_alumno_id, evento_id, nombre_alumno, operacion,
      mesa_extra_cantidad_antes,       mesa_extra_cantidad_despues,
      mesa_extra_precio_antes,         mesa_extra_precio_despues,
      sillas_extra_cantidad_antes,     sillas_extra_cantidad_despues,
      sillas_extra_precio_total_antes, sillas_extra_precio_total_despues,
      numero_mesa, otras_columnas_cambiadas, usuario, cliente,
      updated_at_antes, updated_at_despues
    ) values (
      new.id, new.evento_id, new.nombre_alumno, lower(tg_op),
      case when tg_op = 'UPDATE' then old.mesa_extra_cantidad end,       new.mesa_extra_cantidad,
      case when tg_op = 'UPDATE' then old.mesa_extra_precio end,         new.mesa_extra_precio,
      case when tg_op = 'UPDATE' then old.sillas_extra_cantidad end,     new.sillas_extra_cantidad,
      case when tg_op = 'UPDATE' then old.sillas_extra_precio_total end, new.sillas_extra_precio_total,
      new.numero_mesa, otras,
      coalesce(auth.jwt() ->> 'email', current_user::text),
      coalesce(hdr ->> 'x-client-info', hdr ->> 'user-agent'),
      case when tg_op = 'UPDATE' then old.updated_at end, new.updated_at
    );
  exception when others then
    -- Si falla, la escritura sigue.
    null;
  end;

  return new;
end;
$$;

drop trigger if exists contratos_alumnos_lugares_cambios on public.contratos_alumnos;
create trigger contratos_alumnos_lugares_cambios
  after insert or update on public.contratos_alumnos
  for each row
  execute function public.anotar_cambio_de_lugares();

-- ── 3. Cómo se lee ─────────────────────────────────────────────────────────

-- Todo lo que se cargó o se sacó en una fiesta, lo más nuevo primero:
-- select cambiado_at at time zone 'America/Argentina/Buenos_Aires' as cuando,
--        nombre_alumno, operacion, numero_mesa,
--        mesa_extra_cantidad_antes   as mesas_antes,  mesa_extra_cantidad_despues   as mesas_despues,
--        sillas_extra_cantidad_antes as sillas_antes, sillas_extra_cantidad_despues as sillas_despues,
--        usuario, cliente, otras_columnas_cambiadas
-- from public.lugares_cambios
-- where evento_id = '<id de la fiesta>'
-- order by cambiado_at desc;

-- La historia de un alumno:
-- select * from public.lugares_cambios
-- where contrato_alumno_id = '<id>'
-- order by cambiado_at;

-- Lo que se cargó DESPUÉS del sorteo de una fiesta (subió la cantidad):
-- select cambiado_at at time zone 'America/Argentina/Buenos_Aires' as cuando,
--        nombre_alumno,
--        coalesce(mesa_extra_cantidad_despues, 0)   - coalesce(mesa_extra_cantidad_antes, 0)   as mesas_de_mas,
--        coalesce(sillas_extra_cantidad_despues, 0) - coalesce(sillas_extra_cantidad_antes, 0) as sillas_de_mas
-- from public.lugares_cambios
-- where evento_id = '<id de la fiesta>'
--   and cambiado_at > '<fecha y hora del sorteo>'
--   and (coalesce(mesa_extra_cantidad_despues, 0)   > coalesce(mesa_extra_cantidad_antes, 0)
--        or coalesce(sillas_extra_cantidad_despues, 0) > coalesce(sillas_extra_cantidad_antes, 0))
-- order by cambiado_at;

-- ── Verificación ───────────────────────────────────────────────────────────
-- select tgname, tgenabled from pg_trigger
--  where tgrelid = 'public.contratos_alumnos'::regclass and not tgisinternal;
-- Tiene que aparecer contratos_alumnos_lugares_cambios, habilitado ('O'), y
-- seguir contratos_alumnos_mora_cambios y el de updated_at.
--
-- La prueba, que no deja nada escrito (termina con un error a propósito y
-- Postgres deshace todo): sobre un alumno cualquiera, sube una silla y mira que
-- quedó la fila; cambia otra columna y mira que no anotó nada.
--
-- do $$
-- declare
--   a      uuid;
--   antes  int;
--   una    int;
--   otra   int;
-- begin
--   select id into a from public.contratos_alumnos order by created_at limit 1;
--   select count(*) into antes from public.lugares_cambios;
--   update public.contratos_alumnos
--      set sillas_extra_cantidad = coalesce(sillas_extra_cantidad, 0) + 1
--    where id = a;
--   select count(*) - antes into una from public.lugares_cambios;
--   update public.contratos_alumnos set updated_at = now() where id = a;
--   select count(*) - antes into otra from public.lugares_cambios;
--   raise exception 'PRUEBA (no queda nada escrito): con la silla anotó % (tiene que ser 1); sin cambio de lugares sigue en % (tiene que ser 1)', una, otra;
-- end $$;
