-- 2026-09-08 — Versionar el trigger de `updated_at`, y taparle los dos agujeros.
--
-- Esta migración es, sobre todo, **documentación ejecutable**: los triggers ya
-- están aplicados en producción desde antes, pero se corrieron a mano en el SQL
-- Editor y nunca quedaron en el repo. El cuerpo de la función todavía tiene los
-- \r\n del pegado desde Windows.
--
-- Eso tiene un costo real: leyendo el repo, la conclusión razonable es que el
-- trigger no existe. De hecho pasó — un plan de septiembre de 2026 propuso
-- "crear" la función y hacer backfill de los NULL, sobre una base que hace rato
-- no tiene un solo `updated_at` nulo. La mitad del plan sobraba y la otra mitad
-- cambiaba de orden de urgencia por esa premisa equivocada.
--
-- Correr esto es inocuo y se puede repetir: `create or replace` sobre la función
-- que ya existe, y `drop trigger if exists` antes de cada `create trigger`.
--
-- Lo único que cambia de verdad son las DOS tablas que se crearon después de
-- aquella tanda manual y quedaron sin trigger:
--
--   * `compromisos_personal` (3 de septiembre) — está en el pull incremental,
--     así que sin trigger una edición nunca cruza a la otra PC: su `updated_at`
--     se queda en el `default now()` del alta y no vuelve a pasar el filtro
--     `.gt(updated_at, marcador)`.
--   * `totem_config`         (4 de septiembre)
--
-- Por qué en el servidor y no en los repos de Dart: el motor de sync no rellena
-- `updated_at` (`_cleanForRemote` solo filtra columnas, no agrega nada), así que
-- depende de que cada repositorio se acuerde de escribirlo. Varios no lo hacen
-- —`presupuestos_repository.dart` no lo menciona una sola vez en sus 516
-- líneas— y con el trigger no hace falta que se acuerden.

-- ── 1. La función ───────────────────────────────────────────────────────────
--
-- Ya existe con este mismo nombre y cuerpo. Se replica acá tal cual para que el
-- repo diga la verdad sobre la base.
--
-- ROLLBACK: no borrar la función mientras haya triggers usándola.

create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── 2. Los triggers ─────────────────────────────────────────────────────────
--
-- `before insert or update` en las dos operaciones: el INSERT también, porque
-- el `default now()` de la columna no cubre a un cliente que mande el campo
-- explícito con una fecha vieja — y el motor de sync manda el payload crudo del
-- repositorio.
--
-- Las 24 tablas que ya lo tienen quedan idénticas. Las dos nuevas están al
-- final de la lista.
--
-- ROLLBACK, por tabla:
--   drop trigger if exists set_updated_at_ins_<tabla> on public.<tabla>;
--   drop trigger if exists set_updated_at_upd_<tabla> on public.<tabla>;

do $$
declare
  t text;
  tablas text[] := array[
    'clientes',
    'servicios',
    'eventos',
    'eventos_servicios',
    'presupuestos',
    'presupuesto_servicios',
    'transacciones',
    'egresos',
    'contratos_alumnos',
    'notas_operativas_contrato',
    'pagos_contrato_alumno',
    'invitados',
    'solicitudes_cotizacion',
    'prestamos_alquiler',
    'prestamo_alquiler_lineas',
    'pagos_prestamo_alquiler',
    'calculos_rentabilidad',
    'obligaciones_pago',
    'caja_fuerte_movimientos',
    'rentabilidad_config',
    'cierre_caja_guia_movimientos',
    'cierre_caja_anotaciones',
    'operadores_caja',
    'sesiones_caja',
    'permisos_usuario',
    -- Las dos que faltaban:
    'compromisos_personal',
    'totem_config'
  ];
begin
  foreach t in array tablas loop
    -- Si la tabla no existe en este proyecto, seguir de largo en vez de abortar
    -- la migración entera.
    if to_regclass('public.' || t) is null then
      raise notice 'sin trigger: la tabla public.% no existe', t;
      continue;
    end if;

    -- Tampoco tiene sentido en una tabla sin la columna.
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = t
        and column_name = 'updated_at'
    ) then
      raise notice 'sin trigger: public.% no tiene updated_at', t;
      continue;
    end if;

    execute format(
      'drop trigger if exists set_updated_at_ins_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_ins_%1$I before insert on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);

    execute format(
      'drop trigger if exists set_updated_at_upd_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_upd_%1$I before update on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);
  end loop;
end $$;

-- ── 3. Limpiar el trigger duplicado de invitados ────────────────────────────
--
-- `invitados` arrastra dos triggers `before update` que hacen exactamente lo
-- mismo: el de esta tanda y `trigger_update_invitados_timestamp`, de
-- `database/invitados_setup.sql`. Inocuo, pero dos triggers para sellar una
-- fecha es ruido, y `invitados` es la única tabla que quedó en la publicación
-- de Realtime — o sea la única cuyos UPDATE escriben WAL que después lee
-- `realtime.apply_rls`. Ahí conviene no tener nada de más.
--
-- ROLLBACK:
--   create trigger trigger_update_invitados_timestamp before update on public.invitados
--     for each row execute function public.update_invitados_updated_at();

drop trigger if exists trigger_update_invitados_timestamp on public.invitados;

-- ── 4. Verificación ─────────────────────────────────────────────────────────
--
-- Después de correr esto, ninguna tabla sincronizada debería quedar sin sus dos
-- triggers. Esta consulta tiene que devolver CERO filas:
--
--   with sincronizadas(tabla) as (values
--     ('clientes'),('servicios'),('eventos'),('eventos_servicios'),
--     ('presupuestos'),('presupuesto_servicios'),('transacciones'),('egresos'),
--     ('contratos_alumnos'),('notas_operativas_contrato'),
--     ('pagos_contrato_alumno'),('invitados'),('solicitudes_cotizacion'),
--     ('prestamos_alquiler'),('prestamo_alquiler_lineas'),
--     ('pagos_prestamo_alquiler'),('calculos_rentabilidad'),
--     ('obligaciones_pago'),('caja_fuerte_movimientos'),('rentabilidad_config'),
--     ('cierre_caja_guia_movimientos'),('cierre_caja_anotaciones'),
--     ('operadores_caja'),('sesiones_caja'),('compromisos_personal'),
--     ('totem_config'))
--   select s.tabla,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from sincronizadas s
--   left join pg_class c   on c.relname = s.tabla
--                         and c.relnamespace = 'public'::regnamespace
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   group by s.tabla
--   having count(*) filter (where t.tgtype & 4  > 0) = 0
--       or count(*) filter (where t.tgtype & 16 > 0) = 0;
